SHELL   := zsh
VARIANT ?= debug
NODE_ENV ?= development
PLATFORM := $(shell rustc -vV 2>/dev/null | sed -n 's|host: ||p')

export VARIANT NODE_ENV PLATFORM

CARGO_FLAGS    :=
WASM_PACK_FLAGS :=
ifeq ($(VARIANT),release)
  CARGO_FLAGS     := --release
  WASM_PACK_FLAGS := --release
endif

.PHONY: all \
        web web-wasm web-rust typescript-web \
        native native-cmake native-rust typescript-server \
        test test-web test-native \
        install-web install-native \
        format format-native lint \
        sbom \
        clean init dev

# ── Default ───────────────────────────────────────────────────────────────────

all: web

# ── Web-app (emscripten + wasm-pack + TypeScript) ─────────────────────────────

web: web-wasm web-rust typescript-web

web-wasm:
	emcmake cmake -S . -B .cmake-emscripten -G Ninja
	cmake --build .cmake-emscripten

web-rust:
	cargo build $(CARGO_FLAGS)
	wasm-pack build $(WASM_PACK_FLAGS) --target web --out-dir target/npm-pkg

typescript-web:
	npm run build --workspace=typescript

# ── Native (cmake + cargo + server bundle) ────────────────────────────────────

native: native-cmake native-rust typescript-server

native-cmake:
	cmake -G Ninja -S . -B .cmake --preset $(VARIANT)
	cmake --build .cmake

native-rust:
	cargo build $(CARGO_FLAGS)

typescript-server:
	npm run build:server --workspace=typescript

# ── Tests ─────────────────────────────────────────────────────────────────────

test: test-web test-native

test-web:
	emcmake ctest --test-dir .cmake-emscripten
	cargo test
	npm run test --workspace=typescript

test-native:
	ctest --test-dir .cmake
	cargo test
	npm run test --workspace=typescript

# ── Install ───────────────────────────────────────────────────────────────────

install-web:
	mkdir -p ./output/bin ./output/wasm
	cp -a ./typescript/dist/* ./output/bin
	chmod +x ./output/bin/*
	cp -a target/npm-pkg/* ./output/wasm/

install-native:
	mkdir -p ./output/bin ./output/lib
	cp -a ./typescript/dist/* ./output/bin
	chmod +x ./output/bin/*
	cp -a target/$(VARIANT)/lib*.so ./output/lib/ 2>/dev/null || true
	cp -a .cmake/lib*.so ./output/lib/ 2>/dev/null || true

# ── Formatting & Linting ──────────────────────────────────────────────────────

format: format-native
	nix fmt
	npm run prettier --workspace=typescript
	cargo fmt

format-native:
	find ./native -type f -name '*.c' -o -name '*.cc' -o -name '*.cpp' \
	  -o -name '*.c++' -o -name '*.h' -o -name '*.h++' -o -name '*.cxx' \
	  -o -name '*.m' -o -name '*.mm' -exec clang-format -i {} +

lint:
	npm run lint --workspace=typescript
	run-clang-tidy -checks "clang-analyzer-*,bugprone-*,portability-*,cert-*,darwin-*,objc-*,concurrency-*,boost-*" -fix -p .cmake -j4

# ── SBOM ──────────────────────────────────────────────────────────────────────

sbom:
	mkdir -p sbom
	npm sbom --workspace=typescript --sbom-format cyclonedx --output-file sbom/npm-sbom.cdx.json
	cargo metadata --format-version 1 > sbom/cargo-metadata.json

# ── Housekeeping ──────────────────────────────────────────────────────────────

clean:
	rm -rf dist target node_modules typescript/node_modules \
	  .expo .cmake .cmake-emscripten output result .build

init:
	npm install
	npx husky install
	git submodule update --init --recursive
	cargo fetch

dev:
	node_modules/.bin/dotenvx run -- \
	  node_modules/.bin/concurrently --kill-others \
	  'bacon --headless' \
	  'npm run start --workspace=typescript'
