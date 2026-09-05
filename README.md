# Device tree for Motorola Edge 2025 (oulu)

TWRP device tree for the Motorola Edge 2025 (XT2519-1), codename **oulu**, chipset
MediaTek mt6878. Built against
[minimal-manifest-twrp/platform_manifest_twrp_aosp](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp)
(`twrp-14.1` branch, TeamWin `android-14.1`, AOSP `android-14.0.0_r67`).

## Status

**Not yet tested on hardware.** The build compiles cleanly and produces a
`vendor_boot.img` whose contents have been verified (correct header, correct TWRP
ramdisk fragment, stock platform ramdisk/dtb preserved byte-for-byte via
`repack_vendor_boot.sh` — see below) but nothing has been flashed to a device yet.

**FBE (file-based encryption) support is currently disabled** — see the commented-out
block in `BoardConfig.mk` for why. TeamWin's `android-14.1` `bootable/recovery` (libtar)
calls fscrypt helper functions (`get_policy_size`, `get_policy_descriptor`, `get_policy`,
`get_policy_content`, `fscrypt_policy_size`) that aren't defined anywhere in that same
branch's `system/vold` or `vendor/twrp/libfscrypt` — an upstream inconsistency, not a
local misconfiguration (verified `bootable/recovery` is at the exact tip of its pinned
branch). Until that's resolved upstream or worked around, TWRP will not be able to
decrypt `/data` on this device.

## Building

```
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-14.1 --depth=1 --no-tags --git-lfs
repo sync -c --no-tags
git clone https://github.com/JeremyDoege89/android_device_motorola_oulu device/motorola/oulu

source build/envsetup.sh
lunch twrp_oulu-ap2a-eng
export ALLOW_MISSING_DEPENDENCIES=true   # this minimal manifest is intentionally partial
mka vendorbootimage bootimage -j<N>
```

`ALLOW_MISSING_DEPENDENCIES=true` is required — the minimal manifest omits whole
subsystems (Car framework, NeuralNetworks, several test/CTS trees), and Soong analyzes
the entire checked-out tree regardless of build target.

## Flashing

This device has **no dedicated recovery partition** — TWRP lives as a `recovery`
ramdisk fragment inside `vendor_boot`. The build's raw `vendor_boot.img` is **not**
directly flashable: this is a recovery-only minimal tree with no `vendor_dlkm`/kernel
module sources, so its platform ramdisk fragment comes out empty and its dtb comes out
empty. Flashing it as-is would very likely break normal Android boot, not just recovery.

Use `repack_vendor_boot.sh` to transplant only the TWRP recovery fragment into a stock
`vendor_boot` image pulled from the device, keeping the stock platform fragment and dtb
intact:

```
STOCK=/path/to/stock_vendor_boot.img ./device/motorola/oulu/repack_vendor_boot.sh
fastboot flash vendor_boot out/target/product/oulu/vendor_boot-twrp.img
```

The script reproduces the stock header exactly (via `unpack_bootimg --format=mkbootimg`)
rather than hand-copied values, and refuses to produce an image larger than the 64 MiB
`vendor_boot` partition.

## Hardware reference

BoardConfig values (partition sizes, offsets, storage/crypto flags, display timing) were
derived from partition images and `/proc` output pulled directly from a running device —
not guessed. See comments in `BoardConfig.mk` and `recovery.fstab` for details and
caveats (in particular the logical/dynamic-partition device naming under
`recovery.fstab`, which is marked TODO pending a real boot test).

## License

Apache License 2.0 — see `LICENSE`. Matches the licensing of the AOSP and TWRP source
this tree builds against.

