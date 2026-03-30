# Project template flake — multi-language monorepo (Rust, TypeScript, Swift, C/C++)
# that produces native binaries, WASM modules, a web app, and Docker images.
#
# Nix reference: https://nixos.org/manual/nixpkgs/stable/
{
  # ── Flake inputs (pinned dependency sources) ────────────────────────
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils"; # helpers for multi-system boilerplate
    rust-overlay.url = "github:oxalica/rust-overlay"; # provides specific Rust toolchains via overlay
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs"; # ensure rust-overlay uses our pinned nixpkgs
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    let
      lib = nixpkgs.lib;
      supportedSystems = with flake-utils.lib.system; [
        x86_64-linux
        aarch64-linux
        x86_64-darwin
        aarch64-darwin
      ];

      # ── Rust binary discovery ─────────────────────────────────────
      # Automatically discovers all Rust binary targets so we don't
      # have to maintain a manual list. Mirrors Cargo's own discovery:
      #   1. Explicit [[bin]] entries in Cargo.toml
      #   2. src/main.rs  (uses the package name)
      #   3. src/bin/*.rs  and  src/bin/*/main.rs
      # ── Swift binary discovery ─────────────────────────────────
      # Automatically discovers Swift executable targets by scanning
      # for Sources/*/main.swift (the Swift convention for executables).
      swiftBinNames =
        let
          srcDir = ./swift/Sources;
        in
        if builtins.pathExists srcDir then
          let
            entries = builtins.readDir srcDir;
            names = builtins.attrNames entries;
          in
          builtins.filter (
            n: entries.${n} == "directory" && builtins.pathExists (srcDir + "/${n}/main.swift")
          ) names
        else
          [ ];

      # ── SwiftPM dependency management (via swiftpm2nix) ──────────
      # swiftpm2nix generates Nix expressions from `swift package resolve`
      # output, enabling offline builds in Nix's sandbox. The generated
      # files live in swift/nix/ and are checked into the repo.

      cargoToml = builtins.fromTOML (builtins.readFile ./rust/Cargo.toml);
      rustBinNames =
        let
          # [[bin]] entries declared explicitly in Cargo.toml
          explicit = if cargoToml ? bin then map (b: b.name) cargoToml.bin else [ ];
          # Default binary from src/main.rs (named after the package)
          main = if builtins.pathExists ./rust/src/main.rs then [ cargoToml.package.name ] else [ ];
          binDir = ./rust/src/bin;
          # Auto-discovered binaries from the src/bin/ directory:
          #   - single-file binaries: src/bin/foo.rs
          #   - directory binaries:   src/bin/foo/main.rs
          auto =
            if builtins.pathExists binDir then
              let
                entries = builtins.readDir binDir;
                names = builtins.attrNames entries;
              in
              (map (n: lib.removeSuffix ".rs" n) (
                builtins.filter (n: entries.${n} == "regular" && lib.hasSuffix ".rs" n) names
              ))
              ++ (builtins.filter (
                n: entries.${n} == "directory" && builtins.pathExists (binDir + "/${n}/main.rs")
              ) names)
            else
              [ ];
        in
        lib.unique (explicit ++ main ++ auto);

      # ── Helper functions ────────────────────────────────────────

      # Instantiate nixpkgs for a given system with the Rust overlay applied.
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
          config.allowUnfree = false;
        };

      # Stable Rust toolchain with additional WASM compilation targets.
      mkRustToolchain =
        pkgs:
        pkgs.rust-bin.stable.latest.default.override {
          targets = [
            "wasm32-unknown-unknown" # browser WASM (no system interface)
            "wasm32-wasip1" # WASI preview 1 (runs in wasmtime)
          ];
        };

      # Build a Rust platform (cargo + rustc pair) using our chosen toolchain.
      mkRustPlatform =
        pkgs:
        let
          rt = mkRustToolchain pkgs;
        in
        pkgs.makeRustPlatform {
          cargo = rt;
          rustc = rt;
        };

      # Create a minimal source tree containing only the Makefile and one
      # subdirectory. This keeps Nix store inputs small and avoids unnecessary
      # rebuilds when unrelated files change.
      mkSrcWith =
        dir:
        lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./Makefile
            dir
          ];
        };

      # Build the Rust crate as a browser-targeted WASM package using
      # wasm-bindgen. The output (JS glue + .wasm) is consumed by the
      # TypeScript/web app build.
      mkWasmPkg =
        pkgs:
        (mkRustPlatform pkgs).buildRustPackage {
          pname = "wasm-pkg";
          version = "0.1.0";
          src = ./rust;
          cargoLock.lockFile = ./rust/Cargo.lock;
          nativeBuildInputs = [ pkgs.wasm-bindgen-cli ];
          buildPhase = ''
            runHook preBuild
            cargo build --target wasm32-unknown-unknown --release
            runHook postBuild
          '';
          doCheck = false;
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            wasm-bindgen --target web --out-dir $out \
              target/wasm32-unknown-unknown/release/rust.wasm
            runHook postInstall
          '';
        };

      # Build each discovered Rust binary as a WASI module and wrap it with
      # wasmtime so it can be executed like a normal CLI program.
      # Produces one derivation per binary in rustBinNames.
      mkWasmBins =
        pkgs:
        let
          rustPlatform = mkRustPlatform pkgs;
        in
        builtins.listToAttrs (
          map (binName: {
            name = binName;
            value = rustPlatform.buildRustPackage {
              pname = binName;
              version = cargoToml.package.version;
              src = ./rust;
              cargoLock.lockFile = ./rust/Cargo.lock;
              nativeBuildInputs = [ pkgs.makeWrapper ];
              buildPhase = ''
                runHook preBuild
                cargo build --target wasm32-wasip1 --release --bin ${binName}
                runHook postBuild
              '';
              doCheck = false;
              installPhase = ''
                runHook preInstall
                mkdir -p $out/lib $out/bin
                cp target/wasm32-wasip1/release/${binName}.wasm $out/lib/
                makeWrapper ${pkgs.wasmtime}/bin/wasmtime $out/bin/${binName} \
                  --add-flags "$out/lib/${binName}.wasm"
                runHook postInstall
              '';
              meta.mainProgram = binName;
            };
          }) rustBinNames
        );
    in
    # ── Per-system outputs ──────────────────────────────────────────
    flake-utils.lib.eachSystem supportedSystems (
        system:
        let
          pkgs = mkPkgs system;
          rustToolchain = mkRustToolchain pkgs;
          rustPlatform = mkRustPlatform pkgs;
          wasmPkg = mkWasmPkg pkgs;
          swiftpmGenerated = pkgs.swiftpm2nix.helpers ./swift/nix;

          # ── Development tools (shared by devShell and builds) ──────
          devTools =
            with pkgs;
            [
              git
              zsh
              pkg-config
              cmake
              ninja
              python3
              which
              clang
              lld
              clang-tools
              esbuild
              rustToolchain
              bacon
              wasm-pack
              wasm-bindgen-cli
              swift
              swiftPackages.swiftpm
              swiftpm2nix
              swiftPackages.Dispatch
              swiftPackages.Foundation
              nodejs
            ]
            ++ lib.optionals pkgs.stdenv.isLinux [ gnustep-libobjc ]
            ++ lib.optionals pkgs.stdenv.isDarwin [ apple-sdk ];

          # ── Package derivations ───────────────────────────────────

          # Native Rust binaries (one per discovered bin target, prefixed "rust-")
          rustBins = builtins.listToAttrs (
            map (binName: {
              name = "rust-${binName}";
              value = rustPlatform.buildRustPackage {
                pname = binName;
                version = cargoToml.package.version;
                src = ./rust;
                cargoLock.lockFile = ./rust/Cargo.lock;
                cargoBuildFlags = [
                  "--bin"
                  binName
                ];
                cargoTestFlags = [
                  "--bin"
                  binName
                ];
              };
            }) rustBinNames
          );

          # Native Swift binaries (one per discovered executable target, prefixed "swift-")
          swiftBins = builtins.listToAttrs (
            map (binName: {
              name = "swift-${binName}";
              value = pkgs.swiftPackages.stdenv.mkDerivation {
                pname = binName;
                version = "0.1.0";
                src = mkSrcWith ./swift;
                nativeBuildInputs =
                  with pkgs;
                  [
                    swift
                    swiftPackages.swiftpm
                    makeWrapper
                  ]
                  ++ lib.optionals pkgs.stdenv.isLinux [
                    swiftPackages.Dispatch
                    swiftPackages.Foundation
                  ];
                env = lib.optionalAttrs pkgs.stdenv.isLinux {
                  LD_LIBRARY_PATH = "${pkgs.swiftPackages.Dispatch}/lib";
                };
                configurePhase = ''
                  cd swift
                  ${swiftpmGenerated.configure}
                '';
                buildPhase = ''
                  export HOME=$TMPDIR
                  swift build -c release --product ${binName}
                '';
                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/bin
                  buildDir=$(swift build -c release --show-bin-path)
                  cp "$buildDir/${binName}" $out/bin/.${binName}-wrapped
                  # Copy any Swift resource bundles alongside the binary
                  for bundle in "$buildDir"/*.resources; do
                    [ -e "$bundle" ] && cp -r "$bundle" $out/bin/
                  done
                  makeWrapper $out/bin/.${binName}-wrapped $out/bin/${binName} \
                    ${lib.optionalString pkgs.stdenv.isLinux "--set LD_LIBRARY_PATH ${pkgs.swiftPackages.Dispatch}/lib"}
                  runHook postInstall
                '';
                meta.mainProgram = binName;
              };
            }) swiftBinNames
          );

          # C/C++/Objective-C shared library built with clang + CMake/Ninja
          nativeLib = pkgs.clangStdenv.mkDerivation {
            name = "native-lib";
            src = mkSrcWith ./native;
            nativeBuildInputs =
              with pkgs;
              [
                zsh
                cmake
                ninja
                lld
              ]
              ++ lib.optionals pkgs.stdenv.isLinux [ gnustep-libobjc ]
              ++ lib.optionals pkgs.stdenv.isDarwin [ apple-sdk ];
            env.PROJECT_NAME = "native-lib";
            configurePhase = "true";
            buildPhase = "make build-native";
            checkPhase = "make test-native";
            installPhase = ''
              mkdir -p $out/lib
              cp native/build/libcore.so $out/lib/ 2>/dev/null || true
              cp native/build/libcore.dylib $out/lib/ 2>/dev/null || true
            '';
          };

          # Rust library crate (produces .rlib / .so / .dylib)
          rustLib = rustPlatform.buildRustPackage {
            pname = "rust-lib";
            version = "0.1.0";
            src = ./rust;
            cargoLock.lockFile = ./rust/Cargo.lock;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib
              find target -path "*/release/librust*" -type f -exec cp {} $out/lib/ \;
              runHook postInstall
            '';
          };

          # Swift library (compiled modules + object files)
          swiftLib = pkgs.swiftPackages.stdenv.mkDerivation {
            name = "swift-lib";
            src = mkSrcWith ./swift;
            nativeBuildInputs =
              with pkgs;
              [
                swift
                swiftPackages.swiftpm
              ]
              # On Darwin, Dispatch/Foundation/XCTest are provided by the Apple SDK
              ++ lib.optionals pkgs.stdenv.isLinux [
                swiftPackages.Dispatch
                swiftPackages.Foundation
                swiftPackages.XCTest
              ];
            env = lib.optionalAttrs pkgs.stdenv.isLinux {
              LD_LIBRARY_PATH = "${pkgs.swiftPackages.Dispatch}/lib";
            };
            configurePhase = ''
              cd swift
              ${swiftpmGenerated.configure}
              cd ..
            '';
            buildPhase = ''
              export HOME=$TMPDIR
              make build-swift
            '';
            checkPhase = ''
              export HOME=$TMPDIR
              make test-swift
            '';
            installPhase = ''
              mkdir -p $out/lib/swift
              buildDir=$(cd swift && swift build -c release --show-bin-path)
              cp "$buildDir"/*.swiftmodule "$buildDir"/*.swiftdoc "$buildDir"/*.swiftsourceinfo $out/lib/swift/ 2>/dev/null || true
              cp "$buildDir"/project_template.build/*.o $out/lib/ 2>/dev/null || true
            '';
          };

          # TypeScript web application — bundles the WASM package, native lib,
          # Rust lib, and Swift lib into a deployable artifact with:
          #   - Expo static export + Node.js server (bin/main.js)
          #   - Cloudflare Worker bundle (worker/worker.js)
          typescriptApp = pkgs.buildNpmPackage {
            pname = "typescript-app";
            version = "0.0.0";
            src = ./typescript;
            npmDeps = pkgs.importNpmLock { npmRoot = ./typescript; };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;
            nativeBuildInputs = with pkgs; [
              zsh
              esbuild
              removeReferencesTo
            ];
            env.NODE_ENV = "production";
            env.ESBUILD_BINARY_PATH = "${pkgs.esbuild}/bin/esbuild";
            preBuild = ''
              export HOME=$TMPDIR
              mkdir -p ../rust/target/npm-pkg
              cp -r ${wasmPkg}/* ../rust/target/npm-pkg/
            '';
            buildPhase = ''
              runHook preBuild
              # Expo static export + Node server
              npm run build
              # Cloudflare Worker entry point
              npx esbuild src/worker.ts --outfile=./dist/worker.js --platform=browser --bundle --minify --format=esm '--external:node:*'
              runHook postBuild
            '';
            checkPhase = "npx jest";
            installPhase = ''
              runHook preInstall
              make -f ${./Makefile} install \
                DIST=$out \
                TS_DIST=dist \
                NATIVE_LIB=${nativeLib}/lib \
                RUST_LIB=${rustLib}/lib \
                SWIFT_LIB=${swiftLib}/lib
              # Strip build-time references. The native artifacts in lib/
              # embed paths to the Swift/LLVM/Clang toolchain (~2.8GB)
              # via swift-lib → clang-wrapper → clang-lib → llvm-lib.
              # These .o/.swiftmodule files are not loaded at runtime so
              # stripping their toolchain refs is safe.
              find $out -type f -exec remove-references-to \
                -t ${pkgs.nodejs} \
                -t ${nativeLib} \
                -t ${rustLib} \
                -t ${swiftLib} \
                -t ${pkgs.swiftPackages.swift.swift.lib} \
                {} +
              runHook postInstall
            '';
            passthru.runtimeDeps = with pkgs; [
              nodejs-slim
              litestream
            ];
            meta.mainProgram = "main.js";
          };

          # Thin wrapper around typescriptApp that copies the final artifacts
          # into a clean output (bin/, lib/, worker/) for deployment.
          webApp = pkgs.stdenv.mkDerivation {
            name = "web-app";
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            dontCheck = true;
            runtimeDeps = typescriptApp.runtimeDeps;
            buildInputs = typescriptApp.runtimeDeps;
            nativeBuildInputs = [ pkgs.removeReferencesTo ];
            installPhase = ''
              mkdir -p $out
              cp -a ${typescriptApp}/bin $out/
              cp -a ${typescriptApp}/lib $out/
              cp -a ${typescriptApp}/worker $out/
              # Strip the reference to typescriptApp itself — all files
              # are already copied into $out so the original is not needed.
              find $out -type f -exec remove-references-to \
                -t ${typescriptApp} \
                {} +
            '';
            meta.mainProgram = "main.js";
          };

          # Debug variant (same build, different name for identification)
          webAppDebug = webApp.overrideAttrs (_: {
            name = "web-app-debug";
          });

          # ── Docker image builder ──────────────────────────────────
          # Creates a layered OCI image with two systemd services:
          #   1. node-server  — the Node.js Express backend
          #   2. litestream   — SQLite replication (only starts if LITESTREAM_URL is set)
          # The image uses systemd as PID 1 to manage both services.
          buildImage =
            pkg:
            let
              port = "8081";

              litestreamConfig = pkgs.writeTextDir "etc/litestream.yml" ''
                dbs:
                  - path: /app/data.db
                    replicas:
                      - url: $LITESTREAM_URL
              '';

              systemdUnits = pkgs.runCommand "systemd-units" { } ''
                # Symlink systemd's own unit files (targets, etc.) into a
                # standard search path so PID 1 can find default.target,
                # multi-user.target, and friends inside the container.
                mkdir -p $out/lib/systemd
                ln -s ${pkgs.systemdMinimal}/lib/systemd/system $out/lib/systemd/system

                mkdir -p $out/etc/systemd/system/multi-user.target.wants

                cat > $out/etc/systemd/system/node-server.service <<'EOF'
                [Unit]
                Description=Node.js Express Server

                [Service]
                Type=simple
                ExecStart=${pkgs.nodejs-slim}/bin/node ${pkg}/bin/${pkg.meta.mainProgram}
                WorkingDirectory=/app
                PassEnvironment=BACKEND_LISTEN_PORT BACKEND_LISTEN_HOSTNAME DISABLE_CLUSTER
                Restart=always
                RestartSec=3

                [Install]
                WantedBy=multi-user.target
                EOF

                cat > $out/etc/systemd/system/litestream.service <<'EOF'
                [Unit]
                Description=Litestream SQLite Replication
                After=node-server.service
                ConditionEnvironment=LITESTREAM_URL

                [Service]
                Type=simple
                ExecStartPre=${pkgs.busybox}/bin/sh -c 'until [ -f /app/data.db ]; do sleep 1; done'
                ExecStart=${pkgs.litestream}/bin/litestream replicate -config /etc/litestream.yml
                WorkingDirectory=/app
                PassEnvironment=LITESTREAM_URL
                Restart=always
                RestartSec=5

                [Install]
                WantedBy=multi-user.target
                EOF

                ln -s ../node-server.service $out/etc/systemd/system/multi-user.target.wants/
                ln -s ../litestream.service $out/etc/systemd/system/multi-user.target.wants/
              '';
            in
            pkgs.dockerTools.buildLayeredImage {
              name = pkg.name;
              contents = pkg.runtimeDeps ++ [
                pkgs.busybox
                pkgs.systemdMinimal
                litestreamConfig
                systemdUnits
              ];
              config = {
                Cmd = [ "${pkgs.systemdMinimal}/lib/systemd/systemd" ];
                WorkingDir = "/app";
                Env = [
                  "BACKEND_LISTEN_PORT=${port}"
                  "BACKEND_LISTEN_HOSTNAME=0.0.0.0"
                ];
                ExposedPorts.${port} = { };
                Healthcheck = {
                  Test = [
                    "${pkgs.curlMinimal}/bin/curl"
                    "-f"
                    "-s"
                    "localhost:${port}/api/status"
                  ];
                  Interval = 30000000000;
                  Timeout = 10000000000;
                  Retries = 3;
                };
                Volumes."/app" = { };
              };
            };
        in
        rec {
          # ── Exported packages ──────────────────────────────────────
          # Build with: nix build .#<name>   (e.g. nix build .#web-app)
          packages = {
            "web-app" = webApp;
            "web-app-debug" = webAppDebug;
            "native-lib" = nativeLib;
            "rust-lib" = rustLib;
            "swift-lib" = swiftLib;
            "typescript-app" = typescriptApp;
            cloudflare = pkgs.stdenv.mkDerivation {
              name = "cloudflare";
              dontUnpack = true;
              dontConfigure = true;
              dontBuild = true;
              dontCheck = true;
              installPhase = ''
                mkdir -p $out
                cp ${typescriptApp}/worker/worker.js $out/
                cp -r ${typescriptApp}/worker/assets $out/
              '';
            };
            default = webApp;
          }
          // rustBins # merge in native Rust binary packages (rust-<name>)
          // swiftBins # merge in native Swift binary packages (swift-<name>)
          # WASM packages — platform-independent output built using this system's toolchain
          // { "wasm-pkg" = mkWasmPkg pkgs; }
          // (mkWasmBins pkgs)
          # Docker images require busybox + systemd, which are Linux-only
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            "docker-image" = buildImage webApp;
            "docker-image-debug" = buildImage webAppDebug;
          };
          # `nix flake check` builds every package except "default" (which
          # is an alias and would duplicate work).
          checks = builtins.removeAttrs packages [ "default" ];

          # ── Development shell ──────────────────────────────────────
          # Enter with: nix develop
          # Provides all compilers, tools, and a VSCodium instance with
          # pre-configured extensions for the full polyglot stack.
          devShells.default = pkgs.mkShell {
            packages = devTools;
            env.ESBUILD_BINARY_PATH = "${pkgs.esbuild}/bin/esbuild";
          };
          formatter = pkgs.nixfmt-tree; # `nix fmt` uses nixfmt-tree
        }
      );
}
