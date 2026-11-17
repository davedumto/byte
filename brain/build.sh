#!/bin/sh
# Cross-compile llama-server for the iPod (iOS 15, A10, arm64), CPU only (NEON), static, then fake-sign with ldid.
# Output: brain/out/llama-server
set -eu
cd "$(dirname "$0")"

LLAMA_TAG=b12444                 # pinned release; bump deliberately
SRC=llama.cpp
BUILD=build-ios
OUT=out

[ -d "$SRC" ] || git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$SRC"
HAVE=$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || echo unknown)
[ "$HAVE" = "$LLAMA_TAG" ] || { echo "llama.cpp is at $HAVE, expected $LLAMA_TAG" >&2; exit 1; }

# -mcpu=apple-a10: the A10 is ARMv8.0-class with no dot-product or fp16 arithmetic.
# Code tuned for newer chips would hit illegal instructions on the iPod.
CPU_FLAGS="-mcpu=apple-a10"

cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_MACOSX_BUNDLE=OFF \
  -DCMAKE_C_FLAGS="$CPU_FLAGS" -DCMAKE_CXX_FLAGS="$CPU_FLAGS" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_ACCELERATE=OFF \
  -DGGML_OPENMP=OFF \
  -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_SERVER=ON

cmake --build "$BUILD" --config Release --target llama-server -j "$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
BIN=$(find "$BUILD" -type f -name llama-server -perm -u+x | head -1)
[ -n "$BIN" ] || { echo "llama-server binary not found" >&2; exit 1; }
cp "$BIN" "$OUT/llama-server"
ldid -S "$OUT/llama-server"
# The launcher (lifts the 6 MB daemon memory limit, drops to mobile, execs llama-server).
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 $CPU_FLAGS -O2 -Wall -Wextra -Werror \
  -o "$OUT/byte-brain-launcher" launcher/byte-brain-launcher.c
ldid -Slauncher/entitlements.plist "$OUT/byte-brain-launcher"

echo "built $OUT/llama-server ($(wc -c < "$OUT/llama-server" | tr -d ' ') bytes) from llama.cpp $LLAMA_TAG"
