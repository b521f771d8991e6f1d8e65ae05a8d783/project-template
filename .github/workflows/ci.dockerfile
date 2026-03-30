FROM ghcr.io/b521f771d8991e6f1d8e65ae05a8d783/base-tools/debian-tools-2:main

WORKDIR /build
COPY . .
RUN --mount=type=cache,target=/build/native/build \
  --mount=type=cache,target=/build/swift/.build \
  --mount=type=cache,target=/build/rust/target \
  --mount=type=cache,target=/usr/local/cargo/registry \
  --mount=type=cache,target=/build/typescript/node_modules \
  (cd typescript && npm install) && \
  make all