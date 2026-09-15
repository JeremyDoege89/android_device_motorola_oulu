# Device tree for Motorola Edge 2025 (oulu)

TWRP device tree for the Motorola Edge 2025 (XT2519-1), codename **oulu**, chipset
MediaTek mt6878. Built against
[minimal-manifest-twrp/platform_manifest_twrp_aosp](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp)
(`twrp-14.1` branch, TeamWin `android-14.1`, AOSP `android-14.0.0_r67`).

## Status

**Boots and runs on hardware.** Verified on an XT2519-1 with an unlocked bootloader.

| | |
|---|---|
| Boots to TWRP unattended | working |
| Touchscreen | working |
| Display / theme scaling | working (1220x2712) |
| adb from within TWRP | working |
| SELinux | enforcing (recovery domain permissive — see below) |
| Decrypt / mount `/data` | **not working** — see FBE below |
| USB OTG storage | untested |
| MTP | disabled on purpose — see below |

Stock firmware reference: `motorola/oulu_g_sys/oulu:16/W1VDS36H.50-38-3-8`. Note the
GRF split — system is Android 16 (SDK 36) while **vendor is frozen at Android 14**,
which is why a `twrp-14.1` base is a reasonable match for the vendor HALs.

### FBE (file-based encryption)

`/data` uses fscrypt v2 with **hardware-wrapped keys**:

```
fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0
metadata_encryption=aes-256-xts:wrappedkey_v0
```

Two layers must be defeated: metadata encryption (dm-default-key) blocks even *mounting*
the filesystem, and FBE blocks reading files afterwards. `wrappedkey_v0` means the keys
never exist in plaintext — KeyMint unwraps them in hardware, so the vendor Trustonic
(Kinibi) TEE stack has to be running inside the recovery ramdisk.

**The compile-side blocker is solved** (see `patches/`). TeamWin's `android-14.1`
`bootable/recovery/libtar` calls a version-agnostic fscrypt API — `get_policy`,
`get_policy_descriptor`, `get_policy_content`, `get_policy_size`, `fscrypt_policy_size`
over a `fscrypt_policy` type — that its paired `system/vold` does not provide; vold only
exports `fscrypt_policy_v1`/`_v2` with `lookup_ref_key` / `lookup_ref_tar` /
`fscrypt_policy_get_struct`. `patches/bootable_recovery/` bridges the two, and libtar now
builds cleanly with `TW_INCLUDE_CRYPTO_FBE`. (Upstream has an equivalent unmerged fix in
TWRP Gerrit change 8745.)

**What remains** is the runtime side: oulu's own Trustonic binaries, their transitive
library closure, the `mcRegistry` trustlets, matching VINTF fragments and the init
ordering (`/mnt/vendor/persist` → `mcDriverDaemon` → TEE → gatekeeper → KeyMint), plus
`hwservicemanager`, which this ramdisk currently lacks. The crypto flags in
`BoardConfig.mk` are therefore **left commented out** until those exist — enabling them
alone builds but cannot decrypt.

## Getting a tree that builds

TeamWin's `bootable/recovery` and `vendor/twrp` both need fixes this device depends on
that are not upstream yet. Two ways to get them.

**Option A - local manifest (recommended).** Forks carrying the fixes are pinned by
`local_manifest.xml`, so `repo sync` just works:

```
mkdir -p .repo/local_manifests
cp device/motorola/oulu/local_manifest.xml .repo/local_manifests/oulu.xml
repo sync -c --no-tags
```

**Option B - apply the patches by hand** to TeamWin's trees. Same changes, kept here so
the delta stays reviewable and upstreamable:

```
cd bootable/recovery && git apply /path/to/device/motorola/oulu/patches/bootable_recovery/*.patch
cd vendor/twrp      && git apply /path/to/device/motorola/oulu/patches/vendor_twrp/*.patch
```

- `bootable_recovery/0001` — AOSP module renames (`*-ndk_platform` → `*-ndk`,
  `keystore2-V1` → `V4`) and a `task_profiles.json` dependency move.
- `bootable_recovery/0002` + `0003` — the libtar/vold fscrypt bridge described above.
- `vendor_twrp/0001` — `build/tasks/kernel.mk` invokes the recipe macro
  `$(call twrp-depmod)` outside any target, so make aborts with *"commands commence
  before first target"*. Only triggers when `TW_LOAD_VENDOR_MODULES` is set **and**
  `TARGET_PREBUILT_KERNEL` is defined — i.e. exactly this configuration.

## Building

```
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-14.1 --depth=1 --no-tags --git-lfs
repo sync -c --no-tags
git clone https://github.com/JeremyDoege89/android_device_motorola_oulu device/motorola/oulu
# then apply patches/ as above

source build/envsetup.sh
lunch twrp_oulu-ap2a-eng
export ALLOW_MISSING_DEPENDENCIES=true

# Soong defines an install rule for the recovery variant of libresetprop but it is not in
# vendorbootimage's dependency chain, so force it first or the recovery binary will not
# link at runtime ("CANNOT LINK EXECUTABLE ... libresetprop.so not found").
mka out/target/product/oulu/recovery/root/system/lib64/libresetprop.so

mka vendorbootimage
```

Two invocation notes: `lunch twrp_oulu-eng` is rejected by this AOSP — the release config
must be named, hence `twrp_oulu-ap2a-eng`. And `ALLOW_MISSING_DEPENDENCIES=true` is
required because the minimal manifest omits whole subsystems while Soong still analyses
the entire checkout.

### Stale artifacts in `recovery/root`

There is **no** Soong install rule for the recovery variant of `libminuitwrp`, so a
rebuilt copy only lands in `system/lib64` and `recovery/root` silently keeps whatever an
earlier build left there. After changing anything that affects it (e.g.
`TARGET_RECOVERY_PIXEL_FORMAT`):

```
cp -p out/target/product/oulu/system/lib64/libminuitwrp.so \
      out/target/product/oulu/recovery/root/system/lib64/libminuitwrp.so
rm -f out/target/product/oulu/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp
rm -f out/target/product/oulu/obj/PACKAGING/vendor_ramdisk_fragments_intermediates/recovery.cpio.lz4
```

**Verify the packed image, not the build log.** Unpack the fragment and confirm the bits
you changed actually made it in, e.g.
`strings -a system/lib64/libminuitwrp.so | grep "setting DRM_FORMAT"`.

## Flashing

This device has **no dedicated recovery partition** — TWRP lives as a `recovery` ramdisk
fragment inside `vendor_boot`. The build's raw `vendor_boot.img` is **not** directly
flashable: this recovery-only tree has no `vendor_dlkm`/kernel module sources, so its
platform ramdisk fragment and dtb come out empty, and flashing it would break normal
Android boot, not just recovery.

`repack_vendor_boot.sh` transplants only the TWRP recovery fragment into a stock
`vendor_boot` pulled from the device, keeping the stock platform fragment and dtb intact:

```
env -u OUT OUT=$HOME/vendor_boot-twrp.img \
    STOCK=/path/to/stock_vendor_boot.img ./device/motorola/oulu/repack_vendor_boot.sh
fastboot flash vendor_boot_a $HOME/vendor_boot-twrp.img
```

`env -u OUT` is needed because `envsetup.sh` exports `OUT` as a *directory*, which the
script would otherwise use as its output *file*.

Prebuilt images are published under **Releases** rather than committed to the repo.

## Notable device specifics

- **Pixel format must be set.** Without `TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"`,
  minuitwrp's DRM path falls into a buggy default branch that allocates a 16bpp RGB565
  dumb buffer but renders into it at 32bpp, so TWRP segfaults painting the splash.
- **`init.recovery.mt6878.rc` is mandatory.** First-stage init imports
  `/init.recovery.${ro.hardware}.rc`; it sets `sys.usb.configfs`/`sys.usb.controller`
  (without which USB never enumerates at all) and runs `mtk_plpath_utils`, which creates
  the `/dev/block/by-name/*` symlinks the fstab depends on. It ships in the *stock*
  recovery fragment, so replacing that fragment with TWRP's drops it.
- **`servicemanager` needs a bootstrap linker.** Its ELF interpreter is
  `/system/bin/bootstrap/linker64`, which the ramdisk does not ship, so `execv` fails with
  ENOENT even though the binary exists. The rc creates a symlink in `on early-init`.
- **Touch is a vendor module.** The panel is Goodix behind Motorola's `mmi` framework and
  none of it is in the vendor_boot ramdisk; `TW_LOAD_VENDOR_MODULES` pulls the five
  modules off `vendor_dlkm` in dependency order.
- **MTP is disabled deliberately.** TWRP enables MTP by setting `sys.usb.config=mtp,adb`,
  but `bootable/recovery/etc/init.rc` has configfs triggers only for `adb`, `fastboot`,
  `sideload` and `none`. The `none` trigger tears the gadget down and nothing matches
  `mtp,adb` to rebuild it, so USB dies the moment TWRP starts. `TW_EXCLUDE_MTP := true`
  keeps adb alive instead.
- **SELinux.** Stock policy confines the `recovery` domain far too tightly for TWRP
  (denied `write` on rootfs, `twrp.*` property sets, `dm_device` ioctls), so
  `sepolicy/recovery.te` marks that domain permissive. This is scoped to recovery only —
  normal Android loads its policy from the stock system/vendor partitions, which this
  tree never builds or flashes.
- **No microSD slot.** There is no mmc/msdc controller under `/sys/devices/platform`, so
  there is no `/external_sd` entry.

## Known issues

- `/data` cannot be decrypted or mounted (see FBE above). Anything depending on it —
  backups, dalvik wipe, internal storage — fails accordingly.
- USB OTG is declared in the fstab but has not been confirmed working.
- APEX images fail to loop-mount in recovery (`Value too large for defined data type`).
- If a stale `boot-recovery` command is left in the BCB, *every* boot lands in recovery.
  Clear it with `dd if=/dev/zero of=/dev/block/by-name/misc bs=1024 count=2` — only the
  first 2048 bytes, since A/B `bootloader_control` lives at offset 2048 and
  `fastboot erase misc` would destroy slot selection.

## Hardware reference

BoardConfig values (partition sizes, offsets, storage/crypto flags, display timing) were
derived from partition images and `/proc` output pulled directly from a running device —
not guessed. See comments in `BoardConfig.mk` and `recovery.fstab`.

## License

Apache License 2.0 — see `LICENSE`. Matches the licensing of the AOSP and TWRP source
this tree builds against.
