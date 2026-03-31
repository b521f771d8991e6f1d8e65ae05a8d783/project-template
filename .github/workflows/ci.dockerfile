FROM ghcr.io/b521f771d8991e6f1d8e65ae05a8d783/base-tools/debian-tools-2:main AS development

FROM development AS build

WORKDIR /build
COPY typescript/package.json typescript/package-lock.json typescript/
RUN cd typescript && npm install
COPY . .
RUN --mount=type=cache,target=/build/native/build \
  --mount=type=cache,target=/build/swift/.build \
  --mount=type=cache,target=/build/rust/target \
  --mount=type=cache,target=~/.cargo \
  --mount=type=cache,target=~/.swiftpm \
  --mount=type=cache,target=/build/typescript/.expo \
  --mount=type=cache,target=/tmp/metro-cache \
  make
  