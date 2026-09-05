#!/bin/bash
# Repack a flashable vendor_boot.img for motorola oulu (Moto Edge 2025, mt6878).
#
# Why this exists: the build produces a structurally correct vendor_boot.img, but its
# platform ramdisk fragment is empty and its dtb is absent, because this minimal
# recovery-only tree has no vendor_dlkm/modules to generate them from. That fragment
# carries the vendor kernel modules required for NORMAL Android boot, so flashing the
# build output directly would bootloop the device.
#
# This script takes the STOCK vendor_boot pulled from the device and replaces ONLY its
# "recovery" ramdisk fragment with the TWRP one we built, keeping the stock platform
# fragment, stock dtb, stock bootconfig and stock header verbatim.
#
# It reproduces the stock header exactly by reusing the argument list that
# unpack_bootimg emits (--format=mkbootimg), so no header value is hand-copied.

set -euo pipefail

TOP="${TOP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
MKBOOTIMG="$TOP/system/tools/mkbootimg/mkbootimg.py"
UNPACK="$TOP/system/tools/mkbootimg/unpack_bootimg.py"

STOCK="${STOCK:-$HOME/oulu_partitions/backup_slot_b/vendor_boot_b.img}"
# Source of the TWRP recovery ramdisk: the vendor_boot.img this tree just built. Taking it
# from the built image rather than from a *.cpio.{gz,lz4} intermediate means we always get
# whatever the build actually emitted, with no stale-intermediate or compression-extension
# guessing (BOARD_RAMDISK_USE_LZ4 changes that extension).
BUILT="${BUILT:-$TOP/out/target/product/oulu/vendor_boot.img}"
OUT="${OUT:-$TOP/out/target/product/oulu/vendor_boot-twrp.img}"

# Must match BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE in BoardConfig.mk.
PART_SIZE=67108864

for f in "$MKBOOTIMG" "$UNPACK" "$STOCK" "$BUILT"; do
    [ -f "$f" ] || { echo "ERROR: missing required file: $f" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "stock image : $STOCK"
echo "built image : $BUILT"
echo "output      : $OUT"
echo

# Extract the TWRP recovery fragment from the image we just built, by name.
python3 "$UNPACK" --boot_img "$BUILT" --out "$WORK/built" >/dev/null
TWRP_FRAGMENT="$WORK/built/vendor-ramdisk-by-name/ramdisk_recovery"
[ -e "$TWRP_FRAGMENT" ] || {
    echo "ERROR: built image has no 'recovery' ramdisk fragment." >&2
    echo "       Check BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT in BoardConfig.mk." >&2
    exit 1
}
TWRP_FRAGMENT="$(readlink -f "$TWRP_FRAGMENT")"

# Unpack the stock image and capture the exact arguments needed to rebuild it.
declare -a ARGS=()
while IFS= read -r -d '' arg; do
    ARGS+=("$arg")
done < <(python3 "$UNPACK" --boot_img "$STOCK" --out "$WORK" --format=mkbootimg -0)

# Locate the recovery fragment by NAME (not by index) via the by-name symlinks.
RECOVERY_FRAGMENT="$WORK/vendor-ramdisk-by-name/ramdisk_recovery"
[ -e "$RECOVERY_FRAGMENT" ] || {
    echo "ERROR: stock image has no 'recovery' ramdisk fragment; refusing to guess." >&2
    exit 1
}
RECOVERY_FRAGMENT="$(readlink -f "$RECOVERY_FRAGMENT")"

stock_platform_size=$(stat -c %s "$WORK/vendor_ramdisk00")
stock_recovery_size=$(stat -c %s "$RECOVERY_FRAGMENT")

# The kept stock platform fragment and our recovery fragment end up in the same image.
# Warn if their compression differs from stock's (set BOARD_RAMDISK_USE_LZ4 to match).
magic() { head -c 4 "$1" | od -An -tx1 | tr -s ' ' | sed 's/^ //;s/ $//'; }
stock_magic=$(magic "$WORK/vendor_ramdisk00")
twrp_magic=$(magic "$TWRP_FRAGMENT")
if [ "$stock_magic" != "$twrp_magic" ]; then
    echo "WARNING: compression mismatch between ramdisk fragments." >&2
    echo "         stock platform : $stock_magic" >&2
    echo "         twrp recovery  : $twrp_magic" >&2
    echo "         (02 21 4c 18 = lz4-legacy, 1f 8b 08 00 = gzip)" >&2
    echo "         Set BOARD_RAMDISK_USE_LZ4 := true in BoardConfig.mk to match stock." >&2
    echo >&2
fi

# Swap in TWRP's recovery ramdisk. The captured arguments reference this path, so
# overwriting the file is sufficient - no argument rewriting required.
cp -f "$TWRP_FRAGMENT" "$RECOVERY_FRAGMENT"
new_recovery_size=$(stat -c %s "$RECOVERY_FRAGMENT")

python3 "$MKBOOTIMG" "${ARGS[@]}" --vendor_boot "$OUT"

out_size=$(stat -c %s "$OUT")
if [ "$out_size" -gt "$PART_SIZE" ]; then
    echo >&2
    echo "ERROR: repacked image is ${out_size} bytes, exceeding the ${PART_SIZE}-byte" >&2
    echo "       vendor_boot partition. Refusing to leave an unflashable image in place." >&2
    rm -f "$OUT"
    exit 1
fi

echo
echo "platform fragment kept from stock : ${stock_platform_size} bytes"
echo "recovery fragment ${stock_recovery_size} -> ${new_recovery_size} bytes (TWRP)"
echo "repacked image: ${out_size} / ${PART_SIZE} bytes ($((out_size * 100 / PART_SIZE))% of partition)"
echo
echo "Verify before flashing:"
echo "  python3 $UNPACK --boot_img $OUT --out /tmp/verify_vb"
echo "Then:"
echo "  fastboot flash vendor_boot $OUT"
