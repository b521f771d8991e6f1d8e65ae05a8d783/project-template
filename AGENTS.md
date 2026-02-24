# General

Do not modify [flake.nix](flake.nix). All system-level dependencies are declared there and managed by Nix — do not attempt to install system tools via apt, brew, cargo install, npm install -g, pip, or any other package manager.

For tools needed at runtime, prefer adding them as TypeScript modules (regular `dependencies`, not `devDependencies`) in [package.json](package.json).

## Build Targets ([Makefile](Makefile))

All build orchestration lives in [Makefile](Makefile). Use `make <target>` — do not add build orchestration back to [package.json](package.json).

Override `VARIANT` (default `debug`) and `NODE_ENV` (default `development`) as env vars or on the command line:
```
VARIANT=release make web
```

**Web-app target** (emscripten + wasm-pack + TypeScript — used by `nix build .#web-app`):

| Target | Purpose |
|---|---|
| `make web` | Full web-app build (wasm + rust + typescript) |
| `make web-wasm` | Emscripten cmake only (`.cmake-emscripten`) |
| `make web-rust` | Rust → WASM via cargo + wasm-pack |
| `make typescript-web` | Expo web export + esbuild server bundle |
| `make test-web` | Emscripten ctest + cargo test + jest |
| `make install-web` | Copy web-app artifacts to `./output/` |

**Electron target** (packages the web-app as a desktop app — used by `nix build .#electron-app`):

No Makefile target — this is a pure Nix derivation that takes the `web-app` output and wraps it with `pkgs.electron` via `makeWrapper`. Run with `result/bin/electron-app` after `nix build .#electron-app`.

**Native target** (native cmake + cargo + server bundle — used by `nix build .#native`):

| Target | Purpose |
|---|---|
| `make native` | Full native build (cmake + cargo + server bundle) |
| `make native-cmake` | Native cmake only (`.cmake`) |
| `make native-rust` | Cargo build only, no wasm-pack |
| `make typescript-server` | esbuild server bundle only (no Expo export) |
| `make test-native` | Native ctest + cargo test + jest |
| `make install-native` | Copy native artifacts to `./output/` |

**Shared:**

| Target | Purpose |
|---|---|
| `make test` | Run all tests (both cmake dirs + cargo + jest) |
| `make lint` | Lint TypeScript and native C/C++/ObjC code |
| `make format` | Format all code (nix, prettier, clang-format, rustfmt) |
| `make clean` | Remove all build artifacts |
| `make init` | Init submodules, fetch Cargo deps, `npm install` |
| `make dev` | Start development mode (bacon + TypeScript watch) |

**TypeScript workspace scripts** (called by the Makefile — do not call these directly for top-level builds):

These live in [typescript/package.json](typescript/package.json) and are invoked by the Makefile via `npm run <script> --workspace=typescript`.

| Script | Called by |
|---|---|
| `build` | `make typescript-web` |
| `build:server` | `make typescript-server` |
| `test` | `make test-web` / `make test-native` |
| `lint` | `make lint` |
| `prettier` | `make format` |

## Language Selection

**Default to TypeScript** for all new code unless there is a clear performance reason not to.

Use **Rust** only when:
- CPU-bound work would be a bottleneck in TypeScript (e.g. encoding, parsing, crypto, heavy computation)
- You need deterministic low-latency execution
- The logic will be compiled to WASM and called from the frontend

Use **C/C++/Objective-C** (in [native/](native/)) only when:
- Interfacing directly with a platform API that has no Rust binding
- Wrapping an existing C library

When in doubt, write TypeScript first. Optimize to Rust only if profiling shows it is necessary.

## Project Structure

- [native/](native/) — C, C++, Objective-C, Objective-C++ source (built via CMake + emscripten)
- [rust/](rust/) — Rust library compiled to cdylib/wasm via wasm-pack
- [typescript/](typescript/) — TypeScript workspace (Electron frontend + Node backend)
- [CMakeLists.txt](CMakeLists.txt) — native build definition
- [Cargo.toml](Cargo.toml) — Rust package definition
- [flake.nix](flake.nix) — Nix build environment (do not modify)

## Do Not Modify

These files are either generated or carefully tuned — do not edit them:

- [flake.nix](flake.nix) — Nix environment, all system deps live here
- [flake.lock](flake.lock) — Nix lockfile, updated only by `nix flake update`
- [CMakePresets.json](CMakePresets.json) — compiler flags, sanitizers, warning set
- [Cargo.lock](Cargo.lock) — Rust lockfile, must stay in sync with the Nix build

## Native Code Standards

All native code is compiled with a strict flag set defined in [CMakePresets.json](CMakePresets.json). Write code that respects these constraints:

- **C**: C23 (`CMAKE_C_STANDARD 23`), no extensions
- **C++**: C++26 (`CMAKE_CXX_STANDARD 26`), no extensions
- **Objective-C / Objective-C++**: ObjC23 / ObjC++26, no extensions
- Warnings are errors (`-Wall -Werror -pedantic`). Fix all warnings — do not suppress them.
- Debug builds run AddressSanitizer, LeakSanitizer, and UBSanitizer. Do not use constructs that trip these sanitizers.

## TypeScript Workspace Layout

The project has two `package.json` files with distinct roles:

| File | Role |
|---|---|
| [package.json](package.json) | Root workspace — Electron shell, build/dev scripts, `concurrently`, `dotenvx` |
| [typescript/package.json](typescript/package.json) | TypeScript workspace — Expo/React Native frontend + Express backend |

### Dependency Management

**Never use `devDependencies` in any `package.json` file.** All dependencies — whether runtime or build-time — must be added to `dependencies`. This ensures:
- Clear visibility of what the project needs
- Consistent behavior across all environments (dev, CI, production)
- No hidden dependencies that might break in edge cases

Add new runtime dependencies to [typescript/package.json](typescript/package.json) unless they are build orchestration tools (like Husky, concurrently, dotenvx) that belong at the root.

The TypeScript source is under [typescript/src/](typescript/src/):

- [typescript/src/app/](typescript/src/app/) — Expo Router screens (file-based routing)
- [typescript/src/server/](typescript/src/server/) — Express API routes
- [typescript/src/server.ts](typescript/src/server.ts) — Express entry point (bundled to `dist/main.js` by esbuild)
- [typescript/src/redux/](typescript/src/redux/) — Redux Toolkit state
- [typescript/src/components/](typescript/src/components/) — Shared React Native components

## Electron / Expo Architecture

This app has three contexts. Use the right APIs for each:

| Context | Entry point | Available APIs |
|---|---|---|
| **Electron main** | root [package.json](package.json) `main` → `typescript/dist/main.js` | Full Node.js + Electron APIs |
| **Express server** | [typescript/src/server.ts](typescript/src/server.ts) | Full Node.js, no DOM, no Electron renderer APIs |
| **Expo frontend** | [typescript/src/app/](typescript/src/app/) | React Native / browser APIs only — no `fs`, no `child_process` |

Cross-context communication must go through the Express HTTP API or Electron IPC — do not import server-side modules into frontend code.

Styling uses **NativeWind** (Tailwind CSS for React Native). Use Tailwind utility classes via `className` props rather than `StyleSheet`.

## Build Verification

It is imperative that `nix build` succeeds. **`nix build` must pass before every commit** — this is enforced by the pre-commit hook (see [Pre-commit Hook](#pre-commit-hook) below).

Always verify your changes build cleanly before finishing a task.

**Before finishing any task, run `nix build` for every target that could be affected by your changes:**

```
nix build .#web-app       # if you touched wasm/emscripten/TypeScript web code
nix build .#electron-app  # if you touched the Electron shell or web-app output
nix build .#native        # if you touched native cmake/cargo/server code
```

Run all three if you are unsure which targets are affected. A successful `nix build` is the authoritative test — it runs in a clean, reproducible environment and catches issues that local builds may miss.

## Pre-commit Hook

A shared pre-commit hook enforces that `nix build` passes before every commit. The hook is managed by [Husky](https://typicode.github.io/husky/) and lives in [.husky/pre-commit](.husky/pre-commit).

**Setup** (run once after cloning):
```
make init
```

This installs npm dependencies and initializes Husky hooks. The pre-commit hook will automatically run before every commit and block any commit where `nix build` fails, with helpful output directing you to fix the issues.

To bypass the hook in an emergency (not recommended), use:
```
git commit --no-verify
```

However, commits that fail the build will be caught at push time and should not be merged to main.

Additionally, before finishing any task, run:
```
make format
make lint
make test-web    # if you touched web-app code (wasm/emscripten)
make test-native # if you touched native code (cmake/cargo)
```

Use `make test` to run both suites together. The default `VARIANT=debug` enables sanitizers locally. The Nix build sets `VARIANT=release` automatically.

## Localization (l10n)

All user-visible strings must be translated. When adding any new string to the frontend:

1. Add the key to **every** locale file in [typescript/src/i18n/locales/](typescript/src/i18n/locales/).
2. Never hardcode a display string in a component — always use `t("key")` from `react-i18next`.

The supported locales are:

| File | Language |
|---|---|
| `en.json` | English |
| `de.json` | German |
| `fr.json` | French |
| `es.json` | Spanish |
| `pt.json` | Portuguese |
| `ru.json` | Russian |
| `ar.json` | Arabic |
| `zh.json` | Chinese |
| `he.json` | Hebrew |
| `la.json` | Latin |

If you add a new language, register it in [typescript/src/i18n/index.ts](typescript/src/i18n/index.ts).

## Testing

Write tests for each action you implement:
- **Native cmake (C/C++)**: add `ctest` tests in [CMakeLists.txt](CMakeLists.txt); verified by `test:native`
- **Emscripten cmake**: add `ctest` tests in [CMakeLists.txt](CMakeLists.txt); verified by `test:web`
- **Rust (native)**: add `#[test]` in [rust/](rust/); run via `make test-native`
- **Rust (WASM)**: add `#[wasm_bindgen_test]` in [rust/](rust/); run via `make test-web`
- **TypeScript**: add Jest tests in [typescript/src/\_\_tests\_\_/](typescript/src/__tests__/)
