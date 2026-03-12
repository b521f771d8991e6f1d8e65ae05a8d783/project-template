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

          # Build tools shared across targets.
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

            # rust tools (includes wasm32-unknown-unknown target)
            rustToolchain
            bacon
            wasm-pack
            wasm-bindgen-cli

            # swift tools
            swift
            swiftPackages.swiftpm
            swiftPackages.Dispatch
            swiftPackages.Foundation

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

          # Swift library, built with swiftPackages.stdenv for Foundation support.
          swiftLib = pkgs.swiftPackages.stdenv.mkDerivation {
            name = "swift-lib";
            src = ./.;

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

          # Builds Rust, native C/C++, Swift and Node into one web-app output.
          webApp = rustPlatform.buildRustPackage {
            name = "web-app";
            src = ./.;

            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            env = {
              CC = "${pkgs.clang}/bin/clang";
              CXX = "${pkgs.clang}/bin/clang++";
              OBJC = webApp.CC;
              OBJCXX = webApp.CXX;

              VARIANT = "release";
              NODE_ENV = "production";
              PROJECT_NAME = "web-app";
            };

            npmDeps = pkgs.importNpmLock { npmRoot = ./.; };

            nativeBuildInputs = commonNativeBuildInputs;

            runtimeDeps = with pkgs; [
              nodejs-slim
              litestream
            ];

            buildInputs = webApp.runtimeDeps;

            buildPhase = ''
              export HOME=$TMPDIR/home
              mkdir -p $HOME
              CC=${webApp.CC} CXX=${webApp.CXX} SWIFT_LIB_PREBUILT=${swiftLib} make web
            '';

            # swift test requires swiftPackages.stdenv; run it via swiftLib instead
            checkPhase = ''
              ctest --test-dir .cmake
              cargo test
              npm run test --workspace=typescript
            '';

            installPhase = ''
              mkdir -p $out
              make install-web
              mv ./output/* $out
              cp -a ${swiftLib}/lib/* $out/lib/
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
            docker-image = buildImage webApp;
            "docker-image-debug" = buildImage webAppDebug;
            default = webApp;
          };

          checks = builtins.removeAttrs packages [ "default" ];

          formatter = pkgs.nixfmt-tree;
        }
      );
}
