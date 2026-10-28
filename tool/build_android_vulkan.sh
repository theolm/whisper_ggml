#!/usr/bin/env bash
#
# Rebuilds android/src/main/jniLibs/arm64-v8a/libwhisper_vulkan.so.
#
# The Vulkan library is a separate shared object so the API 24 CPU library
# never has to resolve Vulkan 1.1 symbols. Sources are pinned by commit and
# archive checksum; nothing is installed system-wide.
#
# Usage:
#   tool/build_android_vulkan.sh /path/to/scratch
#
# Requires: Python 3, curl, tar, shasum, SDK CMake 3.22.1 and NDK 29.0.13113456.
set -euo pipefail

WORK="${1:?Pass a dedicated scratch directory}"
FORK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK="$SDK/ndk/29.0.13113456"
CMAKE="$SDK/cmake/3.22.1/bin/cmake"
HOST="darwin-x86_64"
if [[ "$(uname -s)" != "Darwin" ]]; then
  HOST="linux-x86_64"
fi

WHISPER_REV=f049fff95a089aa9969deb009cdd4892b3e74916
WHISPER_SHA=279af4ce60dbf397362868f3bacc75b56a4332ac2541cae155070093f6aaf0e3
SPIRV_REV=2a611a970fdbc41ac2e3e328802aed9985352dca
SPIRV_SHA=c2225a49c3d7efa5c4f4ce4a6b42081e6ea3daca376f3353d9d7c2722d77a28a
VULKAN_REV=2cd90f9d20df57eac214c148f3aed885372ddcfe
VULKAN_SHA=e3865307e665f6a4ac4f7bbca7b3ba95e4191c7f8adf9f04b084ef514a2454e9

mkdir -p "$WORK"
cd "$WORK"
WORK="$(pwd)"

download() {
  local url="$1" target="$2" expected="$3"
  if [[ ! -f "$target" || "$(shasum -a 256 "$target" | cut -d' ' -f1)" != "$expected" ]]; then
    rm -f "$target.partial"
    curl -L --fail --silent --show-error -o "$target.partial" "$url"
    if [[ "$(shasum -a 256 "$target.partial" | cut -d' ' -f1)" != "$expected" ]]; then
      echo "Checksum mismatch for $url" >&2
      exit 1
    fi
    mv "$target.partial" "$target"
  fi
}

download "https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/$WHISPER_REV" whisper.tar.gz "$WHISPER_SHA"
download "https://codeload.github.com/KhronosGroup/SPIRV-Headers/tar.gz/$SPIRV_REV" spirv.tar.gz "$SPIRV_SHA"
download "https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/$VULKAN_REV" vulkan.tar.gz "$VULKAN_SHA"

for pair in "whisper.tar.gz:source-whisper" "spirv.tar.gz:source-spirv" "vulkan.tar.gz:source-vulkan"; do
  archive="${pair%%:*}"; prefix="${pair##*:}"
  if [[ ! -d "$prefix" ]]; then
    mkdir -p "$prefix"
    tar -xzf "$archive" --strip-components=1 -C "$prefix"
  fi
done

BUILD_SRC="$WORK/build-src"
rm -rf "$BUILD_SRC"
mkdir -p "$BUILD_SRC"
ln -s "$WORK/source-whisper" "$BUILD_SRC/whisper.cpp"
cp "$FORK_ROOT/android/src/whisper/main.cpp" "$BUILD_SRC/main.cpp"
cp "$FORK_ROOT/android/src/whisper/main.h" "$BUILD_SRC/main.h"
cp "$FORK_ROOT/tool/vulkan/CMakeLists.txt" "$BUILD_SRC/CMakeLists.txt"
python3 "$FORK_ROOT/tool/vulkan/prepare_source.py" "$WORK/source-whisper"
# The plugin vendors dr_wav.h; upstream removed it from examples/.
cp "$FORK_ROOT/android/src/whisper/whisper.cpp/examples/dr_wav.h" \
  "$WORK/source-whisper/examples/dr_wav.h"

mkdir -p "$WORK/spirv-package"
printf 'set(SPIRV-Headers_FOUND TRUE)\n' > "$WORK/spirv-package/SPIRV-HeadersConfig.cmake"

BUILD="$WORK/build-vulkan"
rm -rf "$BUILD"
PATH="$SDK/cmake/3.22.1/bin:$PATH" "$CMAKE" -S "$BUILD_SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$SDK/cmake/3.22.1/bin/ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPIRV-Headers_DIR="$WORK/spirv-package" \
  -DSPIRV_INCLUDE_DIR="$WORK/source-spirv/include" \
  -DVulkan_INCLUDE_DIR="$WORK/source-vulkan/include" \
  -DVulkan_LIBRARY="$NDK/toolchains/llvm/prebuilt/$HOST/sysroot/usr/lib/aarch64-linux-android/28/libvulkan.so" \
  -DVulkan_GLSLC_EXECUTABLE="$NDK/shader-tools/$HOST/glslc" \
  -DWHISPER_DR_WAV_DIR="$FORK_ROOT/android/src/whisper"

PATH="$SDK/cmake/3.22.1/bin:$PATH" "$CMAKE" --build "$BUILD" --target whisper_vulkan --parallel 4

"$NDK/toolchains/llvm/prebuilt/$HOST/bin/llvm-strip" --strip-unneeded "$BUILD/libwhisper_vulkan.so"
mkdir -p "$FORK_ROOT/android/src/main/jniLibs/arm64-v8a"
cp "$BUILD/libwhisper_vulkan.so" \
  "$FORK_ROOT/android/src/main/jniLibs/arm64-v8a/libwhisper_vulkan.so"
shasum -a 256 "$FORK_ROOT/android/src/main/jniLibs/arm64-v8a/libwhisper_vulkan.so"
echo "Rebuilt libwhisper_vulkan.so"
