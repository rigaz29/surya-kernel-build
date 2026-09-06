#!/usr/bin/env bash
#
# Rakit zip AnyKernel3 flashable dari hasil build.sh.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$HOME/surya/kernel_xiaomi_surya}"
OUT="${OUT:-$KERNEL_DIR/out}"
BOOT="$OUT/arch/arm64/boot"
DTS="$BOOT/dts/qcom"
DEST="${DEST:-$HERE/release}"

for f in "$BOOT/Image.gz" "$DTS/surya-sdmmagpie.dtb" "$DTS/surya-sdmmagpie-overlay.dtbo"; do
  [ -f "$f" ] || { echo "!! belum ada: $f (jalankan build.sh dulu)"; exit 1; }
done

RELEASE="$(cat "$OUT/include/config/kernel.release")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -r "$HERE/anykernel/." "$WORK/"

# 1) kernel. surya TIDAK memakai appended DTB
#    (CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE tidak diset), jadi Image.gz polos.
cp "$BOOT/Image.gz" "$WORK/Image.gz"

# 2) dtb -> menggantikan bagian dtb di boot image (boot header v2).
cp "$DTS/surya-sdmmagpie.dtb" "$WORK/dtb"

# 3) dtbo.img -> di-flash ke partisi dtbo oleh write_boot/flash_generic.
python3 "$HERE/tools/mkdtboimg.py" create "$WORK/dtbo.img" \
  --page_size=4096 "$DTS/surya-sdmmagpie-overlay.dtbo"

mkdir -p "$DEST"
ZIP="$DEST/Stormbreaker-surya-${RELEASE%%-openela*}-$(date +%Y%m%d-%H%M).zip"
( cd "$WORK" && zip -r9 "$ZIP" . -x '.git*' >/dev/null )

echo ">> $ZIP"
unzip -l "$ZIP" | grep -E 'Image\.gz|dtb|anykernel\.sh'
