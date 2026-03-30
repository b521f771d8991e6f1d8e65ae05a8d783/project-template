FROM ghcr.io/b521f771d8991e6f1d8e65ae05a8d783/base-tools/debian-tools-2:main

WORKDIR /build
COPY typescript/package.json typescript/package-lock.json typescript/
RUN cd typescript && npm install
COPY . .
RUN --mount=type=cache,target=/build/native/build \
  --mount=type=cache,target=/build/swift/.build \
  --mount=type=cache,target=/build/rust/target/release \
  --mount=type=cache,target=/build/rust/target/wasm32-unknown-unknown \
  --mount=type=cache,target=/usr/local/cargo/registry \
  make