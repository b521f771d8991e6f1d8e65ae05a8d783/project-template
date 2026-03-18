# project-template

Full-stack polyglot template: Expo (React Native + Web) frontend, Express backend, with native libraries in C/C++/Objective-C, Rust, and Swift. Deploys as a Node server or Cloudflare Worker.

## Prerequisites

[Nix](https://nixos.org/) with flakes enabled. All toolchains (clang, Rust, Swift, Node.js, wasm-bindgen, etc.) are provided by the flake.

## Quick start

```bash
nix develop    # enter dev shell with all tools
make dev       # build everything + start Expo dev server
```

## Build targets

| Command | Description |
|---|---|
| `make dev` | Build all libraries + start Expo dev server |
| `make release` | Production build (native + Rust + Swift + WASM + TypeScript) |
| `make debug` | Debug build with sanitizers |
| `make test` | Run all test suites |
| `make clean` | Remove all build artifacts |
| `make format` | Format with `nix fmt` |

Individual targets: `build-native`, `build-rust`, `build-swift`, `build-typescript`, `wasm`, and their debug/test/clean variants.

## Project structure

```
native/       C/C++/Objective-C shared library (CMake + Ninja)
rust/         Rust library + WASM target
swift/        Swift package
typescript/   Expo app (React Native + Web) + Express server + Cloudflare Worker
flake.nix     Nix flake: dev shell, packages, Docker images
Makefile      Orchestrates all builds
```

## Nix packages

```bash
nix build .#web-app          # full app (default)
nix build .#native-lib       # C/C++/ObjC shared library
nix build .#rust-lib          # Rust library
nix build .#swift-lib         # Swift library
nix build .#typescript-app    # TypeScript bundle
nix build .#cloudflare        # Cloudflare Worker bundle
nix build .#docker-image      # Docker image
```
