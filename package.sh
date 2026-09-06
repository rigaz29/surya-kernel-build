#!/usr/bin/env bash
#
# Assemble a flashable AnyKernel3 zip from the build.sh output.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$HOME/surya/kernel_xiaomi_surya}"
OUT="${OUT:-$KERNEL_DIR/out}"
BOOT="$OUT/arch/arm64/boot"
DTS="$BOOT/dts/qcom"
DEST="${DEST:-$HERE/release}"

for f in "$BOOT/Image.gz" "$DTS/surya-sdmmagpie.dtb" "$DTS/surya-sdmmagpie-overlay.dtbo"; do
  [ -f "$f" ] || { echo "!! missing: $f (run build.sh first)"; exit 1; }
done

RELEASE="$(cat "$OUT/include/config/kernel.release")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -r "$HERE/anykernel/." "$WORK/"

# 1) kernel. surya does NOT use an appended DTB
#    (CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE is not set), so this is a plain Image.gz.
cp "$BOOT/Image.gz" "$WORK/Image.gz"

# 2) dtb -> replaces the dtb section of the boot image (boot header v2).
cp "$DTS/surya-sdmmagpie.dtb" "$WORK/dtb"

# 3) dtbo.img -> flashed to the dtbo partition by write_boot/flash_generic.
python3 "$HERE/tools/mkdtboimg.py" create "$WORK/dtbo.img" \
  --page_size=4096 "$DTS/surya-sdmmagpie-overlay.dtbo"

mkdir -p "$DEST"
ZIP="$DEST/Stormbreaker-surya-${RELEASE%%-openela*}-$(date +%Y%m%d-%H%M).zip"
( cd "$WORK" && zip -r9 "$ZIP" . -x '.git*' >/dev/null )

echo ">> $ZIP"
unzip -l "$ZIP" | grep -E 'Image\.gz|dtb|anykernel\.sh'
