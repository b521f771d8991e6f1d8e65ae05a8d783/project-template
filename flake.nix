# for good documentation, see here: https://nixos.org/manual/nixpkgs/stable/
# @AI-Agents: do not add a devshell. Just don't. `nix develop` works just fine without one

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    self.submodules = true;
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    flake-utils.lib.eachSystem
      [
        flake-utils.lib.system.x86_64-linux
        flake-utils.lib.system.aarch64-linux
        flake-utils.lib.system.x86_64-darwin
        flake-utils.lib.system.aarch64-darwin
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
            config = {
              allowUnfree = false;
            };
          };

          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
          };

          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };

          # ── Auto-discover Rust binaries ──────────────────────────────
          cargoToml = builtins.fromTOML (builtins.readFile ./rust/Cargo.toml);

          rustBinNames =
            let
              # [[bin]] entries from Cargo.toml
              explicit = if cargoToml ? bin then map (b: b.name) cargoToml.bin else [ ];
              # src/main.rs → binary named after the package
              main = if builtins.pathExists ./rust/src/main.rs then [ cargoToml.package.name ] else [ ];
              # src/bin/*.rs and src/bin/*/main.rs
              binDir = ./rust/src/bin;
              auto =
                if builtins.pathExists binDir then
                  let
                    entries = builtins.readDir binDir;
                    names = builtins.attrNames entries;
                  in
                  (map (n: pkgs.lib.removeSuffix ".rs" n) (
                    builtins.filter (n: entries.${n} == "regular" && pkgs.lib.hasSuffix ".rs" n) names
                  ))
                  ++ (builtins.filter (
                    n: entries.${n} == "directory" && builtins.pathExists (binDir + "/${n}/main.rs")
                  ) names)
                else
                  [ ];
            in
            pkgs.lib.unique (explicit ++ main ++ auto);

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

          # ── Native C/C++/ObjC library (CMake + Ninja) ─────────────────
          nativeLib = pkgs.clangStdenv.mkDerivation {
            name = "native-lib";
            src = ./native;

            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              lld
            ];

            env.PROJECT_NAME = "native-lib";

            configurePhase = ''
              cmake -G Ninja -S . -B build --preset release
            '';

            buildPhase = ''
              cmake --build build
            '';

            checkPhase = ''
              ctest --test-dir build
            '';

            installPhase = ''
              mkdir -p $out/lib
              cp build/libcore.so $out/lib/ 2>/dev/null || true
              cp build/libcore.dylib $out/lib/ 2>/dev/null || true
            '';
          };

          # ── Rust native library (buildRustPackage) ─────────────────────
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

          # ── Rust WASM package (buildRustPackage → wasm-bindgen) ────────
          wasmPkg = rustPlatform.buildRustPackage {
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

          # ── Swift library (swiftPackages.stdenv) ───────────────────────
          swiftLib = pkgs.swiftPackages.stdenv.mkDerivation {
            name = "swift-lib";
            src = ./swift;

            nativeBuildInputs = with pkgs; [
              swift
              swiftPackages.swiftpm
              swiftPackages.Dispatch
              swiftPackages.Foundation
              swiftPackages.XCTest
            ];

            buildPhase = ''
              export HOME=$TMPDIR
              export LD_LIBRARY_PATH=${pkgs.swiftPackages.Dispatch}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
              swift build -c release
            '';

            checkPhase = ''
              export HOME=$TMPDIR
              export LD_LIBRARY_PATH=${pkgs.swiftPackages.Dispatch}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
              swift test
            '';

            installPhase = ''
              export LD_LIBRARY_PATH=${pkgs.swiftPackages.Dispatch}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
              mkdir -p $out/lib/swift
              buildDir=$(swift build -c release --show-bin-path)
              cp "$buildDir"/*.swiftmodule "$buildDir"/*.swiftdoc "$buildDir"/*.swiftsourceinfo $out/lib/swift/ 2>/dev/null || true
              cp "$buildDir"/project_template.build/*.o $out/lib/ 2>/dev/null || true
            '';
          };

          # ── TypeScript/Node.js app (buildNpmPackage) ──────────────────
          typescriptApp = pkgs.buildNpmPackage {
            pname = "typescript-app";
            version = "0.0.0";
            src = ./typescript;

            npmDeps = pkgs.importNpmLock { npmRoot = ./typescript; };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;

            nativeBuildInputs = with pkgs; [ zsh ];

            env.NODE_ENV = "production";

            preBuild = ''
              export HOME=$TMPDIR
              # Link WASM package where metro/tsconfig expect it
              mkdir -p ../rust/target/npm-pkg
              cp -r ${wasmPkg}/* ../rust/target/npm-pkg/
            '';

            # npmBuildScript defaults to "build", which runs the package.json build script

            checkPhase = ''
              npx jest
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp -r dist/* $out/bin/
              chmod +x $out/bin/*
              runHook postInstall
            '';
          };

          # ── Combined web app (assembles all components) ────────────────
          webApp = pkgs.stdenv.mkDerivation {
            name = "web-app";
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            dontCheck = true;

            # Dev tools for `nix develop`
            nativeBuildInputs = with pkgs; [
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
              rustToolchain
              bacon
              wasm-pack
              wasm-bindgen-cli
              swift
              swiftPackages.swiftpm
              swiftPackages.Dispatch
              swiftPackages.Foundation
              nodejs
              (vscode-with-extensions.override {
                vscode = vscodium;
                vscodeExtensions =
                  with vscode-extensions;
                  [
                    docker.docker
                    bbenoist.nix
                    streetsidesoftware.code-spell-checker
                    humao.rest-client
                    ms-vscode.cmake-tools
                    esbenp.prettier-vscode
                    dbaeumer.vscode-eslint
                    github.github-vscode-theme
                    christian-kohler.npm-intellisense
                    wix.vscode-import-cost
                    bradlc.vscode-tailwindcss
                    rust-lang.rust-analyzer
                    llvm-vs-code-extensions.vscode-clangd
                  ]
                  ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
                    {
                      name = "excalidraw-editor";
                      publisher = "pomdtr";
                      version = "3.9.1";
                      sha256 = "sha256-/LqC8GUBEDs+yGYCIX8RQtxDmWogTTiTiF/WJiCuEj4=";
                    }
                    {
                      name = "swift-vscode";
                      publisher = "swiftlang";
                      version = "2.16.1";
                      sha256 = "sha256-xNWflrWVU2KHN/w1vDXGD/+/ctpWdrndFi6aHTEhGao=";
                    }
                  ];
              })
            ];

            runtimeDeps = with pkgs; [
              nodejs-slim
              litestream
            ];

            buildInputs = webApp.runtimeDeps;

            installPhase = ''
              mkdir -p $out/bin $out/lib
              cp -a ${typescriptApp}/bin/* $out/bin/
              cp -a ${nativeLib}/lib/* $out/lib/
              cp -a ${rustLib}/lib/* $out/lib/
              cp -a ${swiftLib}/lib/* $out/lib/
            '';

            meta.mainProgram = "main.js";
          };

          webAppDebug = webApp.overrideAttrs (_: {
            name = "web-app-debug";
          });

          buildImage =
            pkg:
            (pkgs.dockerTools.buildLayeredImage (
              let
                backendListenPort = "8081";
              in
              {
                name = pkg.name;
                contents = pkg.runtimeDeps ++ [
                  pkgs.busybox
                ];

                config = {
                  Cmd = [ "${pkg}/bin/${pkg.meta.mainProgram}" ];
                  User = "65534:65534";
                  WorkingDir = "/app";

                  Env = [
                    "BACKEND_LISTEN_PORT=${backendListenPort}"
                  ];

                  ExposedPorts = {
                    "${backendListenPort}" = { };
                  };

                  Healthcheck = {
                    Test = [
                      "${pkgs.curlMinimal}/bin/curl"
                      "-f"
                      "-s"
                      "localhost:${backendListenPort}/api/status"
                    ];
                    Interval = 30000000000;
                    Timeout = 10000000000;
                    Retries = 3;
                  };

                  Volumes = {
                    "/app" = { };
                  };
                };
              }
            ));
        in
        rec {
          packages = {
            "web-app" = webApp;
            "web-app-debug" = webAppDebug;
            "native-lib" = nativeLib;
            "rust-lib" = rustLib;
            "wasm-pkg" = wasmPkg;
            "swift-lib" = swiftLib;
            "typescript-app" = typescriptApp;
            docker-image = buildImage webApp;
            "docker-image-debug" = buildImage webAppDebug;
            default = webApp;
          }
          // rustBins;

          checks = builtins.removeAttrs packages [ "default" ];

          formatter = pkgs.nixfmt-tree;
        }
      );
}
