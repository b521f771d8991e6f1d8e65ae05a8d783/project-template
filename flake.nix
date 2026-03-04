# for good documentation, see here: https://nixos.org/manual/nixpkgs/stable/
# @AI-Agents: do not add a devshell. Just don't. `nix develop` works just fine without one

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    flake-utils.url = "github:numtide/flake-utils";
    self.submodules = true;
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
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
            config = {
              allowUnfree = false;
              # Allow only the Electron binary (unfree due to bundled Chromium).
              allowUnfreePredicate = pkg: builtins.elem pkg.pname [
                "electron"
                "electron-unwrapped"
              ];
            };
          };

          # Build tools shared by both web-app and native targets.
          # Does NOT include wasm toolchain (emscripten, wasm-pack, etc.).
          commonNativeBuildInputs = with pkgs; [
            # general tools
            git
            zsh
            pkg-config
            cmake
            ninja
            python3
            which

            # native tools
            clang
            lld
            clang-tools

            # rust tools
            cargo
            rustc
            rustfmt
            bacon

            # node tools
            nodejs
            pkgs.importNpmLock.npmConfigHook

            (vscode-with-extensions.override {
              vscode = vscodium;
              vscodeExtensions =
                with vscode-extensions;
                [
                  # generic tools
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

                  # languages, typescript is included
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

          # Web-app target: compiles Rust → WASM (wasm-pack) and native C → WASM (emscripten).
          # Produces the Electron/Expo frontend + Express server bundle.
          webApp = pkgs.rustPlatform.buildRustPackage {
            name = "web-app";
            src = ./.;

            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            env = {
              # general flags
              CC = "${pkgs.clang}/bin/clang";
              CXX = "${pkgs.clang}/bin/clang++";
              OBJC = webApp.CC;
              OBJCXX = webApp.CXX;

              VARIANT = "release";
              NODE_ENV = "production";
              ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
              DISPLAY = ":0";
              DONT_PROMPT_WSL_INSTALL = 1;
              PROJECT_NAME = "web-app";
            };

            npmDeps = pkgs.importNpmLock { npmRoot = ./.; };

            nativeBuildInputs = commonNativeBuildInputs ++ (with pkgs; [
              # wasm toolchain
              wasmtime
              emscripten
              wasm-pack
              wasm-bindgen-cli_0_2_104
              binaryen
            ]);

            nativeTools = with pkgs; [
              nodejs-slim
              litestream
            ];

            buildInputs =
              with pkgs;
              webApp.nativeTools;

            buildPhase = ''
              export EM_CACHE=$TMPDIR/emscripten-cache HOME=$TMPDIR/home
              mkdir -p $EM_CACHE $HOME
              CC=${webApp.CC} CXX=${webApp.CXX} make web
            '';

            checkPhase = "make test-web";

            installPhase = ''
              mkdir -p $out
              make install-web
              mv ./output/* $out
              mkdir -p $out/sbom
            '';

            meta.mainProgram = "main.js";
          };

          webAppDebug = webApp.overrideAttrs (old: {
            name = "web-app-debug";
            env = old.env // {
              VARIANT = "debug";
              NODE_ENV = "development";
              PROJECT_NAME = old.name;
            };
          });

          # Native target: compiles Rust and C/C++/ObjC to native platform libraries.
          # No emscripten or wasm-pack — uses make:web:native + make:native:rust.
          native = webApp.overrideAttrs (old: {
            name = "native";
            env = old.env // {
              PROJECT_NAME = "native";
            };
            # Filter out only the wasm toolchain, preserving cargo vendor hooks
            # that buildRustPackage injects (cargoSetupHook etc.).
            nativeBuildInputs = builtins.filter
              (input: !builtins.elem input (with pkgs; [
                wasmtime
                emscripten
                wasm-pack
                wasm-bindgen-cli_0_2_104
                binaryen
              ]))
              old.nativeBuildInputs;
            buildPhase = ''
              export HOME=$TMPDIR/home
              mkdir -p $HOME
              CC=${webApp.CC} CXX=${webApp.CXX} make native
            '';
            checkPhase = "make test-native";
            installPhase = ''
              mkdir -p $out
              make install-native
              mv ./output/* $out
            '';
          });

          nativeDebug = native.overrideAttrs (old: {
            name = "native-debug";
            env = old.env // {
              VARIANT = "debug";
              NODE_ENV = "development";
            };
          });

          # SBOM target: generates CycloneDX (npm) and Cargo metadata SBOMs.
          # --package-lock-only reads the lockfile directly so no node_modules
          # setup (npmConfigHook / npmDeps) is needed — avoiding the Nix store
          # path rewrite that breaks npm sbom's purl generation.
          sbom = pkgs.stdenv.mkDerivation {
            name = "sbom";
            src = ./.;
            nativeBuildInputs = with pkgs; [
              nodejs
              cargo
              rustc
            ];
            buildPhase = "true";
            installPhase = ''
              mkdir -p $out/sbom
              npm sbom --workspace=typescript --package-lock-only --sbom-format cyclonedx --output-file $out/sbom/npm-sbom.cdx.json
              cargo metadata --format-version 1 > $out/sbom/cargo-metadata.json
            '';
          };

          # Electron target: wraps the web-app output with the Nix-provided Electron
          # binary to produce a runnable desktop application.
          electronApp = pkgs.stdenv.mkDerivation {
            name = "electron-app";
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              mkdir -p $out/bin $out/share/electron-app
              cp -r ${webApp}/bin $out/share/electron-app/
              [ -d "${webApp}/wasm" ] && cp -r ${webApp}/wasm $out/share/electron-app/ || true
              makeWrapper ${pkgs.electron}/bin/electron $out/bin/electron-app \
                --add-flags "$out/share/electron-app/bin/electron.js"
            '';

            meta.mainProgram = "electron-app";
          };

          buildImage =
            pkg:
            (pkgs.dockerTools.buildLayeredImage (
              let
                backendListenPort = "8081";
              in
              {
                name = pkg.name;
                contents = pkg.nativeTools ++ [
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
            native = native;
            native-debug = nativeDebug;
            "electron-app" = electronApp;
            docker-image = buildImage webApp;
            "docker-image-debug" = buildImage webAppDebug;
            sbom = sbom;
            default = webApp;
          };

          checks = builtins.removeAttrs packages [ "default" ];

          formatter = pkgs.nixfmt-tree;
        }
      );
}
