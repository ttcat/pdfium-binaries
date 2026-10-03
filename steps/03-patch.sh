#!/bin/bash -eux

PATCHES="$PWD/patches"
SOURCE="${PDFium_SOURCE_DIR:-pdfium}"
OS="${PDFium_TARGET_OS:?}"
TARGET_CPU="${PDFium_TARGET_CPU:?}"
TARGET_ENVIRONMENT="${PDFium_TARGET_ENVIRONMENT:-}"
ENABLE_V8=${PDFium_ENABLE_V8:-false}
BUILD_TYPE=${PDFium_BUILD_TYPE:-shared}

apply_patch() {
  local FILE="$1"
  local DIR="${2:-.}"
  patch --verbose -p1 -d "$DIR" -i "$FILE"
}

pushd "${SOURCE}"

case "$BUILD_TYPE" in
  shared)
    [ "$OS" != "emscripten" ] && apply_patch "$PATCHES/shared_library.patch"
    ;;
  static)
    apply_patch "$PATCHES/static_library.patch"
    ;;
esac

apply_patch "$PATCHES/public_headers.patch"

# xfaconvert（表格轉檔）：XFA 文字可切換成無反鋸齒＋黑白字形對齊，比照 Adobe Acrobat 的圖片匯出。
# 預設行為不變；設定環境變數 PDFIUM_XFA_TEXT_ALIASED=1 才啟用。
apply_patch "$PATCHES/xfaconvert/text.patch"
# 版面用字型的精確字寬（PDFium 原本把字寬截成整數個千分之一 em）；PDFIUM_XFA_EXACT_WIDTH=1 才啟用。
apply_patch "$PATCHES/xfaconvert/width.patch"
# XFA 線條與方框：PDFIUM_XFA_PATH_ALIASED=1 不做反鋸齒、PDFIUM_XFA_STROKE_ADJUST=1 線寬對齊像素（比照 Acrobat）。
apply_patch "$PATCHES/xfaconvert/graphics.patch"
apply_patch "$PATCHES/clang_rt.patch" build

[ "$ENABLE_V8" == "true" ] && apply_patch "$PATCHES/v8/pdfium.patch"

case "$OS" in
  android)
    apply_patch "$PATCHES/android/build.patch" build
    ;;

  ios)
    apply_patch "$PATCHES/ios/pdfium.patch"
    [ "$ENABLE_V8" == "true" ] && apply_patch "$PATCHES/ios/v8.patch" v8
    ;;

  mac)
    apply_patch "$PATCHES/mac/build.patch" build
    ;;

  linux)
    [ "$ENABLE_V8" == "true" ] && apply_patch "$PATCHES/linux/v8.patch" v8
    ;;

  emscripten)
    apply_patch "$PATCHES/wasm/pdfium.patch"
    apply_patch "$PATCHES/wasm/build.patch" build
    if [ "$ENABLE_V8" == "true" ]; then
      apply_patch "$PATCHES/wasm/v8.patch" v8
    fi
    mkdir -p "build/config/wasm"
    cp "$PATCHES/wasm/config.gn" "build/config/wasm/BUILD.gn"
    ;;

  win)
    apply_patch "$PATCHES/win/pdfium.patch"
    apply_patch "$PATCHES/win/build.patch" build

    VERSION=${PDFium_VERSION:-0.0.0.0}
    YEAR=$(date +%Y)
    VERSION_CSV=${VERSION//./,}
    export YEAR VERSION VERSION_CSV
    envsubst < "$PATCHES/win/resources.rc" > "resources.rc"
    ;;
esac

case "$TARGET_ENVIRONMENT" in
  musl)
    apply_patch "$PATCHES/musl/pdfium.patch"
    apply_patch "$PATCHES/musl/build.patch" build
    mkdir -p "build/toolchain/linux/musl"
    cp "$PATCHES/musl/toolchain.gn" "build/toolchain/linux/musl/BUILD.gn"
    ;;
esac

case "$TARGET_CPU" in
  mipsel|mips64el)
    apply_patch "$PATCHES/mips64el/build.patch" build
    ;;
  ppc64)
    apply_patch "$PATCHES/ppc64/pdfium.patch"
    apply_patch "$PATCHES/ppc64/build.patch" build
    ;;
esac

popd
