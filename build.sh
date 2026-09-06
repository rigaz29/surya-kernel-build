#!/usr/bin/env bash
#
# Build kernel Xiaomi surya (Poco X3 NFC) - sm8150/sdmmagpie, Linux 4.14 ELTS.
# Lihat README.md untuk penjelasan tiap keputusan di skrip ini.
#
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-$HOME/surya/kernel_xiaomi_surya}"
TC_DIR="${TC_DIR:-$HOME/surya/toolchain/proton-clang}"
TC_URL="https://github.com/kdrag0n/proton-clang.git"
DEFCONFIG="${DEFCONFIG:-surya_defconfig}"
JOBS="${JOBS:-$(nproc)}"

[ -d "$KERNEL_DIR" ] || { echo "!! KERNEL_DIR tidak ada: $KERNEL_DIR"; exit 1; }

# --- toolchain ---------------------------------------------------------------
if [ ! -x "$TC_DIR/bin/clang" ]; then
  echo ">> Mengunduh Proton Clang ke $TC_DIR (~1.6 GB, sekali saja)"
  mkdir -p "$(dirname "$TC_DIR")"
  git clone --depth=1 "$TC_URL" "$TC_DIR"
fi

# dtc sistem harus cukup baru untuk mendukung orphan node pada overlay dtbo
# (diuji dengan dtc 1.7.0 dari Ubuntu 24.04). dtc in-tree tidak bisa dipakai.
DTC_EXT="${DTC_EXT:-$(command -v dtc || true)}"
[ -n "$DTC_EXT" ] || { echo "!! dtc tidak ditemukan. Pasang: apt install device-tree-compiler"; exit 1; }

# PENTING: toolchain ditaruh di AKHIR PATH. Kalau di depan, binutils 2.36 bawaan
# Proton menaungi binutils sistem dan host tool (fixdep) gagal di-link pada
# glibc >= 2.36 karena section .relr.dyn belum dikenali ld 2.36.
# clang / ld.lld / llvm-* namanya unik jadi tetap terambil dari toolchain.
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
echo ">> Selesai: $(cat out/include/config/kernel.release)"
ls -la out/arch/arm64/boot/Image.gz out/arch/arm64/boot/dts/qcom/surya-sdmmagpie.dtb \
       out/arch/arm64/boot/dts/qcom/surya-sdmmagpie-overlay.dtbo
