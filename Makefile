# ── Toolchain ─────────────────────────────────────────────────────

CC  := $(shell command -v clang)
CXX := $(shell command -v clang++)

# Objective-C runtime (GNUstep on Linux)
OBJC_CFLAGS     := $(shell pkg-config --cflags libobjc 2>/dev/null || gnustep-config --objc-flags 2>/dev/null)
OBJC_LINK_FLAGS := $(shell pkg-config --libs libobjc 2>/dev/null || gnustep-config --objc-libs 2>/dev/null)
ifeq ($(OBJC_LINK_FLAGS),)
  _LIBOBJC_SO := $(wildcard /nix/store/*-gnustep-libobjc-*/lib/libobjc.so)
  ifneq ($(_LIBOBJC_SO),)
    OBJC_CFLAGS     := -I$(dir $(lastword $(_LIBOBJC_SO)))../include
    OBJC_LIB_DIR    := $(dir $(lastword $(_LIBOBJC_SO)))
  endif
endif

# Swift runtime (libdispatch on Linux)
_LIBDISPATCH_SO := $(wildcard /nix/store/*-swift-corelibs-libdispatch-*/lib/libdispatch.so)
ifneq ($(_LIBDISPATCH_SO),)
  SWIFT_LD_LIBRARY_PATH := $(dir $(lastword $(_LIBDISPATCH_SO)))
endif

NATIVE_CMAKE_FLAGS := \
	-DCMAKE_C_COMPILER=$(CC) \
	-DCMAKE_CXX_COMPILER=$(CXX) \
	-DCMAKE_OBJC_COMPILER=$(CC) \
	-DCMAKE_OBJCXX_COMPILER=$(CXX) \
	$(if $(OBJC_CFLAGS),-DCMAKE_OBJC_FLAGS="$(OBJC_CFLAGS)",) \
	$(if $(OBJC_LIB_DIR),-DCMAKE_LIBRARY_PATH="$(OBJC_LIB_DIR)",)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  NATIVE_RELEASE_PRESET := linux-release
  NATIVE_DEBUG_PRESET   := linux-debug
else
  NATIVE_RELEASE_PRESET := release
  NATIVE_DEBUG_PRESET   := debug
endif

.PHONY: dev release debug test clean wasm format

# ── Development ────────────────────────────────────────────────────

dev:
	$(MAKE) build-native
	$(MAKE) build-rust
	$(MAKE) build-swift
	$(MAKE) wasm
	cd typescript && npm start

# ── Full builds ────────────────────────────────────────────────────

release:
	$(MAKE) build-native
	$(MAKE) build-rust
	$(MAKE) build-swift
	$(MAKE) wasm
	$(MAKE) build-typescript

debug:
	$(MAKE) build-native-debug
	$(MAKE) build-rust-debug
	$(MAKE) build-swift-debug
	$(MAKE) wasm
	$(MAKE) build-typescript

# ── Native (C/C++) ─────────────────────────────────────────────────

.PHONY: build-native build-native-debug test-native clean-native

build-native:
	cd native && PROJECT_NAME=native-lib cmake -G Ninja -S . -B build --preset $(NATIVE_RELEASE_PRESET) $(NATIVE_CMAKE_FLAGS)
	cd native && cmake --build build

build-native-debug:
	cd native && PROJECT_NAME=native-lib cmake -G Ninja -S . -B build --preset $(NATIVE_DEBUG_PRESET) $(NATIVE_CMAKE_FLAGS)
	cd native && cmake --build build

test-native:
	cd native && ctest --test-dir build

clean-native:
	rm -rf native/build

# ── Rust ───────────────────────────────────────────────────────────

.PHONY: build-rust build-rust-debug test-rust clean-rust

build-rust:
	cd rust && cargo build --release

build-rust-debug:
	cd rust && cargo build

test-rust:
	cd rust && cargo test

clean-rust:
	cd rust && cargo clean

# ── Swift ──────────────────────────────────────────────────────────

.PHONY: build-swift build-swift-debug test-swift clean-swift

build-swift:
	cd swift && LD_LIBRARY_PATH="$(SWIFT_LD_LIBRARY_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" swift build -c release

build-swift-debug:
	cd swift && LD_LIBRARY_PATH="$(SWIFT_LD_LIBRARY_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" swift build

test-swift:
	cd swift && LD_LIBRARY_PATH="$(SWIFT_LD_LIBRARY_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" swift test

clean-swift:
	cd swift && swift package clean

# ── TypeScript ─────────────────────────────────────────────────────

.PHONY: build-typescript test-typescript clean-typescript

build-typescript:
	cd typescript && npm run build

test-typescript:
	cd typescript && npx jest

clean-typescript:
	rm -rf typescript/dist

# ── WASM ───────────────────────────────────────────────────────────

wasm:
	cd rust && cargo build --target wasm32-unknown-unknown --release
	cd rust && wasm-bindgen --target web --out-dir target/npm-pkg \
		target/wasm32-unknown-unknown/release/rust.wasm

DIST       ?= dist
TS_DIST    ?= typescript/dist
NATIVE_LIB ?= native/build
RUST_LIB   ?= rust/target/release
SWIFT_LIB  ?= $$(cd swift && swift build -c release --show-bin-path)

# ── Install ───────────────────────────────────────────────────────

.PHONY: install dist

dist:
	$(MAKE) release
	$(MAKE) install

install:
	mkdir -p $(DIST)/bin $(DIST)/lib $(DIST)/worker
	cp -r $(TS_DIST)/client $(TS_DIST)/server $(TS_DIST)/main.js $(DIST)/bin/
	chmod +x $(DIST)/bin/main.js
	cp $(TS_DIST)/worker.js $(DIST)/worker/
	cp -r $(TS_DIST)/client $(DIST)/worker/assets
	cp -a $(NATIVE_LIB)/libcore.so $(DIST)/lib/ 2>/dev/null || true
	cp -a $(NATIVE_LIB)/libcore.dylib $(DIST)/lib/ 2>/dev/null || true
	find $(RUST_LIB) -maxdepth 1 -name 'librust*' -type f -exec cp {} $(DIST)/lib/ \;
	find $(SWIFT_LIB) -maxdepth 2 -name '*.o' -exec cp {} $(DIST)/lib/ \; 2>/dev/null || true
	find $(SWIFT_LIB) -maxdepth 2 \( -name '*.swiftmodule' -o -name '*.swiftdoc' -o -name '*.swiftsourceinfo' \) -exec cp {} $(DIST)/lib/ \; 2>/dev/null || true

# ── Aggregate ──────────────────────────────────────────────────────

test:
	$(MAKE) test-native
	$(MAKE) test-rust
	$(MAKE) test-swift
	$(MAKE) test-typescript

clean: clean-native clean-rust clean-swift clean-typescript

format:
	nix fmt
