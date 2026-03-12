SHELL   := zsh
VARIANT ?= debug
NODE_ENV ?= development
PLATFORM := $(shell rustc -vV 2>/dev/null | sed -n 's|host: ||p')

export VARIANT NODE_ENV PLATFORM

CARGO_FLAGS    :=
WASM_TARGET    := wasm32-unknown-unknown
ifeq ($(VARIANT),release)
  CARGO_FLAGS     := --release
endif

.PHONY: all \
        web native-cmake native-rust wasm swift-lib typescript \
        test test-web \
        install-web \
        format format-native lint \
        clean init dev

# ── Default ───────────────────────────────────────────────────────────────────

all: web

# ── Web-app (cmake + cargo + swift + TypeScript) ─────────────────────────────

web: native-cmake native-rust wasm swift-lib typescript

native-cmake:
	cmake -G Ninja -S . -B .cmake --preset $(VARIANT)
	cmake --build .cmake

native-rust:
	cargo build $(CARGO_FLAGS)

wasm:
	cargo build --target $(WASM_TARGET) $(CARGO_FLAGS)
	wasm-bindgen --target web --out-dir target/npm-pkg target/$(WASM_TARGET)/$(VARIANT)/rust.wasm

swift-lib:
ifndef SWIFT_LIB_PREBUILT
	swift build -c $(VARIANT)
else
	@echo "Using prebuilt Swift library from $(SWIFT_LIB_PREBUILT)"
endif

typescript:
	npm run build --workspace=typescript

# ── Tests ─────────────────────────────────────────────────────────────────────

test: test-web

test-web:
	ctest --test-dir .cmake
	cargo test
	swift test
	npm run test --workspace=typescript

# ── Install ───────────────────────────────────────────────────────────────────

install-web:
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

# ── Housekeeping ──────────────────────────────────────────────────────────────

clean:
	rm -rf dist target node_modules typescript/node_modules \
	  .expo .cmake output result .build

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
