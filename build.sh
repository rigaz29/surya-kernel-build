#!/usr/bin/env bash
#
# Build the Xiaomi surya (Poco X3 NFC) kernel - sm8150/sdmmagpie, Linux 4.14 ELTS.
# See README.md for the reasoning behind each decision in this script.
#
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-$HOME/surya/kernel_xiaomi_surya}"
TC_DIR="${TC_DIR:-$HOME/surya/toolchain/proton-clang}"
TC_URL="https://github.com/kdrag0n/proton-clang.git"
DEFCONFIG="${DEFCONFIG:-surya_defconfig}"
JOBS="${JOBS:-$(nproc)}"

[ -d "$KERNEL_DIR" ] || { echo "!! KERNEL_DIR does not exist: $KERNEL_DIR"; exit 1; }

# --- ReSukiSU ----------------------------------------------------------------
# The driver is NOT committed into the kernel tree; it is fetched here and pinned
# to a tested commit so that builds stay reproducible.
KSU_COMMIT="${KSU_COMMIT:-88695111}"
if grep -q '^CONFIG_KSU=y' "$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG" 2>/dev/null \
   && [ ! -f "$KERNEL_DIR/drivers/kernelsu/Makefile" ]; then
  echo ">> Setting up ReSukiSU ($KSU_COMMIT)"
  ( cd "$KERNEL_DIR" && curl -LSs \
      "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" \
      | bash -s "$KSU_COMMIT" )
fi

# --- toolchain ---------------------------------------------------------------
if [ ! -x "$TC_DIR/bin/clang" ]; then
  echo ">> Downloading Proton Clang into $TC_DIR (~1.6 GB, one time only)"
  mkdir -p "$(dirname "$TC_DIR")"
  git clone --depth=1 "$TC_URL" "$TC_DIR"
fi

# The system dtc must be new enough to support orphan nodes in the dtbo overlay
# (tested with dtc 1.7.0 from Ubuntu 24.04). The in-tree dtc cannot be used.
DTC_EXT="${DTC_EXT:-$(command -v dtc || true)}"
[ -n "$DTC_EXT" ] || { echo "!! dtc not found. Install it: apt install device-tree-compiler"; exit 1; }

# IMPORTANT: the toolchain goes LAST on PATH. Placed first, Proton's bundled
# binutils 2.36 shadows the system binutils and linking the host tools (fixdep)
# fails on glibc >= 2.36 because ld 2.36 does not know the .relr.dyn section.
# clang / ld.lld / llvm-* have unique names, so they still come from the toolchain.
export PATH="$PATH:$TC_DIR/bin"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-$(id -un)}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-$(hostname)}"

MAKE_ARGS=(
  O=out ARCH=arm64
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
  READELF=llvm-readelf
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  DTC_EXT="$DTC_EXT"
)

cd "$KERNEL_DIR"
echo ">> clang   : $("$TC_DIR/bin/clang" --version | head -1)"
echo ">> dtc     : $("$DTC_EXT" --version)"
echo ">> host ld : $(ld --version | head -1)"

echo ">> $DEFCONFIG"
make "${MAKE_ARGS[@]}" "$DEFCONFIG"

echo ">> build -j$JOBS"
make "${MAKE_ARGS[@]}" -j"$JOBS"

echo
echo ">> Done: $(cat out/include/config/kernel.release)"
ls -la out/arch/arm64/boot/Image.gz out/arch/arm64/boot/dts/qcom/surya-sdmmagpie.dtb \
       out/arch/arm64/boot/dts/qcom/surya-sdmmagpie-overlay.dtbo
