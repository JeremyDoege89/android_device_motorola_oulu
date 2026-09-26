# Device tree for Motorola Edge 2025 (oulu)

TWRP device tree for the Motorola Edge 2025 (XT2519-1), codename **oulu**, chipset
MediaTek mt6878. Built against
[minimal-manifest-twrp/platform_manifest_twrp_aosp](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp)
(`twrp-14.1` branch, TeamWin `android-14.1`, AOSP `android-14.0.0_r67`).

## Status

**Boots and runs on hardware, decrypts `/data`, and unlocks user storage with the
lock-screen credential.** Verified on an XT2519-1 with an unlocked bootloader.

| | |
|---|---|
| Boots to TWRP unattended | working |
| Touchscreen | working |
| Display / theme scaling | working (1220x2712) |
| adb from within TWRP | working |
| SELinux | enforcing (recovery domain permissive — see below) |
| Trustonic TEE / KeyMint in recovery | **working** |
| Trustonic Gatekeeper HAL in recovery | **working** |
| Metadata decrypt + mount `/data` | **working** |
| Read device-encrypted (DE) data | **working** |
| Unlock credential-encrypted (CE) user files | **working** — confirmed with a pattern lock |
| Data (Nandroid) backup | **working** — confirmed, full 58 GB backup completes cleanly |
| USB OTG storage | untested |
| MTP | disabled on purpose — see below |

Stock firmware reference: `motorola/oulu_g_sys/oulu:16/W1VDS36H.50-38-3-8`. Note the
GRF split — system is Android 16 (SDK 36) while **vendor is frozen at Android 14**,
which is why a `twrp-14.1` base is a reasonable match for the vendor HALs.

> ### ⚠ Update `OULU_SECURITY_PATCH` after every OTA
>
> `BoardConfig.mk` pins the security patch level that the recovery ramdisk advertises.
> KeyMint binds keys to it, so if it stops matching the firmware on the device, **`/data`
> silently stops decrypting**. After an OTA, read the new value in Android with
> `getprop ro.vendor.build.security_patch` and update `OULU_SECURITY_PATCH` to match.

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

**Both layers are solved: `/data` mounts, and it unlocks with the lock-screen
credential.** Getting there needed seven source fixes plus three runtime prerequisites for
the TEE.

#### The seven source fixes

1. **`fscrypt_mount_metadata_encrypted()` was called with the wrong argument slot**
   (`partitionmanager.cpp`). vold's signature is
   `(… fs_type, const std::string& zoned_device, std::string fstab_path = "")`, and TWRP
   passed `additional_fstab` as the **6th** argument — `zoned_device` — instead of the
   7th. One off-by-one produced two unrelated-looking failures: a non-empty
   `zoned_device` makes vold append `/default` to the key directory (stock AOSP zoned
   behaviour, so it reads `<keydir>/default/key` and then demands a
   `<keydir>/zoned/key` that does not exist), while `fstab_path` stayed empty so the
   real fstab was never used.

2. **A 5-field fstab has to exist at `/etc/recovery.fstab`** (`partitionmanager.cpp`).
   `libfs_mgr`'s `ReadDefaultFstab()` hardcodes that path whenever `/system/bin/recovery`
   exists and requires the AOSP 5-field format; TWRP's own fstab is 4-field, so *every*
   fs_mgr consumer in recovery fails with `expected 5 fields, got 4`. That breaks vold
   and it also kills the **boot control HAL**, which needs the fstab to locate `misc`
   (`Could not find bootloader message block device` → `Check failed: impl_.Init()` →
   SIGABRT loop). TWRP now copies the real device fstab to `/etc/recovery.fstab` as well
   as to `/etc/additional.fstab`, once it has mounted `/vendor` and found it.

3. **`cp_needsCheckpoint()` hung forever** (`system/vold/Checkpoint.cpp`, shipped as
   `patches/system_vold/0001`). `MetadataCrypt.cpp` passes it straight into
   `fs_mgr_do_mount()`, and it called `BootControlClient::WaitForService()`, which blocks
   indefinitely because nothing serves `android.hardware.boot.IBootControl/default` in
   recovery. `/data` hung there *after decryption had already succeeded*. All four call
   sites in that file already handle a null module, so they now get one.

4. **The TEE has to be up before the first decrypt attempt** (`partitionmanager.cpp`).
   `Decrypt_Data()` now sets `twrp.tee.start 1` and waits for
   `init.svc.vendor.keymint-trustonic` before trying. It cannot be autostarted from init
   because `mcDriverDaemon` needs `/vendor`, which is a logical partition that only gets
   mapped once TWRP has set up partitions. Getting it right on the *first* attempt also
   matters: a failed attempt leaves a half-built `userdata` dm-default-key device behind,
   and every retry then fails `DM_DEV_CREATE … Device or resource busy` (vold only reuses
   an existing device if it is `SUSPENDED`).

5. **`android.hardware.gatekeeper-V1-ndk.so` was missing from the ramdisk**, so the
   Gatekeeper HAL died at startup with `CANNOT LINK EXECUTABLE … library
   "android.hardware.gatekeeper-V1-ndk.so" not found` and exited status 1 forever.
   Without a running Gatekeeper no lock-screen credential can be verified, so CE storage
   could never unlock. The module has no recovery variant in Soong, so it installs only
   to `system/lib64` and never reaches `recovery/root`; `BOARD_RECOVERY_IMAGE_PREPARE`
   now copies it in from the build's intermediates. Do **not** take this `.so` from the
   device's system partition — that copy is built against `keymint-V4` while this branch
   ships `keymint-V3`, and it pulls the wrong ABI in behind it.

6. **`system/vold/Decrypt.cpp` was calling the wrong gatekeeper interface entirely**
   (`patches/system_vold/`). Even with the HAL running, both of its call sites asked for
   `::android::hardware::gatekeeper::V1_0::IGatekeeper::getService()` — the **HIDL**
   interface. This device's gatekeeper is **AIDL only**
   (`android.hardware.gatekeeper.IGatekeeper/default`), and there is no HIDL gatekeeper
   and no `hwservicemanager` in this ramdisk, so that lookup could never succeed —
   `failed to get gatekeeper service`, `Failed to decrypt user 0`, regardless of the
   credential entered. Ported both call sites to
   `aidl::android::hardware::gatekeeper::IGatekeeper` (`verify()`, no callbacks; it
   returns a `HardwareAuthToken` struct directly, which drops the old HIDL path's
   `hw_auth_token_t` reinterpret-and-byte-swap). Confirmed working on hardware with a
   pattern lock.

7. **`libtar/append.c` overflowed a stack buffer during Data backup** — see the
   "seventh bug" section further down. `patches/bootable_recovery/0005`.

#### What the TEE stack needs at runtime

All three are handled by `init.recovery.tee.rc` + `BoardConfig.mk`; they are listed
because each one on its own is enough to make KeyMint fail with the same opaque
`-49 SECURE_HW_COMMUNICATION_FAILED`.

- **Correct security patch level.** The Trustonic KeyMint HAL reads exactly two
  properties, `ro.build.version.security_patch` and `ro.vendor.build.security_patch`.
  The ramdisk's `prop.default` carries the AOSP branch defaults (`2024-09-05`, and an
  **empty** vendor value), which do not match the device. The mismatch fails
  `HAL_Configure()` with `TlcKM: Failed to read version info.`, after which every call
  returns `Invalid session handle`. `BOARD_RECOVERY_IMAGE_PREPARE` rewrites both.
- **Openable TEE device nodes.** `libMcClient` opens `/dev/mobicore-user`, which is
  `0600 root:root`, while the KeyMint HAL runs as `user system`. TWRP ships no ueventd
  rule for it, so without a `chmod` the HAL gets `Permission denied in open` from
  `ClientLib/src/driver.cpp`.
- **`/vendor` mounted before `mcDriverDaemon` starts.** The trustlet registry is **not**
  bundled — it is ~30 MB against ~4 MB of free space in `vendor_boot`. The daemon reads
  trustlets from `/mnt/vendor/tzapp` and `/vendor/app/mcRegistry`; with `/vendor`
  unmounted it starts with zero trustlets and the TEE is dead.

> **Adding a library to the `TW_INCLUDE_CRYPTO` list is not enough on its own.** Once the
> recovery binary (or `libtar`, or anything else in the crypto path) links it, that piece
> needs it at runtime too, so if it is not also installed into the ramdisk TWRP will not
> start at all. Before packing, check that every `.so` named in
> `strings recovery/root/system/bin/recovery` exists in `recovery/root/system/lib64/` —
> and the same for `libtar.so` and any HAL binary you've touched.

`TW_FORCE_KEYMASTER_VER` is set, but the `keymaster_ver` property turns out to make no
difference here — values `2`, `3`, `4`, `4.0` and `4.1` all behaved identically once the
real blockers were fixed. It is left enabled only because it is harmless.

Confirmed on hardware, in order: metadata decrypt → `/data` mounts → device-encrypted app
data readable → Gatekeeper HAL running → lock-screen **pattern** entered at the TWRP
prompt → credential-encrypted storage unlocks, `/data/media/0` filenames become readable.

#### A seventh bug, found by actually using it: Data backup crashed

The very first real Data backup attempted after CE finally unlocked crashed TWRP outright:

```
libtar:   ==> set selinux context: u:object_r:bootchart_data_file:s0
FORTIFY: vsprintf: prevented 5-byte write into 4-byte buffer
libc: Fatal signal 6 (SIGABRT) ... in tid 463 (recovery)
createTarFork() process ended with signal: 6
Backup Failed. Cleaning Backup Folder.
```

**`libtar/append.c` builds an fscrypt-policy string with a duplicated version prefix.**
`USER_CE_FSCRYPT_POLICY` and its siblings (`system/vold/fscrypt_policy.h`) already embed
the policy version as their first character — `"2CE"` on fscrypt v2, `"0CE"` on v1 — but
`append.c` did:

```c
char user_ce[4], user_de[4], system_de[4];
sprintf(user_ce, "%u%s", t->th_buf.fep->version, USER_CE_FSCRYPT_POLICY);
```

On v2 that's `"2" + "2CE"` = `"22CE"`, 4 characters plus a NUL — 5 bytes into a 4-byte
buffer. `FORTIFY_SOURCE` catches it and kills the process rather than letting it corrupt
memory. This is almost certainly a **pre-existing upstream bug**, not something introduced
by this device's changes — the buggy line only executes when backing up a real,
FBE-decrypted directory tree during a Data Nandroid backup, which was never reachable on
this device (or likely most others building this exact TWRP branch) until CE unlock
itself started working today. Fixed by dropping the redundant version prefix and using
`snprintf` into the correctly-sized buffer (`patches/bootable_recovery/0005`).

The first attempt at this fix (v22) *compiled* clean but changed nothing on the device:
`recovery/root/system/lib64/libtar.so` in the ramdisk was a stale copy from weeks earlier
that no build step ever refreshed, so the crash reproduced byte-for-byte. `libtar.so` is
now copied into the ramdisk from `BOARD_RECOVERY_IMAGE_PREPARE` on every build, the same
fix already applied to `libminuitwrp` and the gatekeeper NDK library elsewhere in this
README — **verify any ramdisk fix by hash against the packed image, never by grepping for
a string or trusting a clean build log.**

**Confirmed fixed on hardware:** a full 58 GB Data backup (35 tar archives) completed in
741 seconds with zero crash.

## Getting a tree that builds

TeamWin's `bootable/recovery`, `vendor/twrp` and `system/vold` all need fixes this device
depends on that are not upstream yet. Two ways to get them.

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
cd system/vold      && git apply /path/to/device/motorola/oulu/patches/system_vold/*.patch
```

- `bootable_recovery/0001` — AOSP module renames (`*-ndk_platform` → `*-ndk`,
  `keystore2-V1` → `V4`) and a `task_profiles.json` dependency move.
- `bootable_recovery/0002` + `0003` — the libtar/vold fscrypt bridge. TeamWin's
  `android-14.1` `libtar` calls a version-agnostic fscrypt API (`get_policy`,
  `get_policy_descriptor`, `get_policy_content`, `get_policy_size`,
  `fscrypt_policy_size`) that its paired `system/vold` does not provide; vold only
  exports `fscrypt_policy_v1`/`_v2` with `lookup_ref_key` / `lookup_ref_tar` /
  `fscrypt_policy_get_struct`. (Upstream has an equivalent unmerged fix in TWRP Gerrit
  change 8745.)
- `vendor_twrp/0001` — `build/tasks/kernel.mk` invokes the recipe macro
  `$(call twrp-depmod)` outside any target, so make aborts with *"commands commence
  before first target"*. Only triggers when `TW_LOAD_VENDOR_MODULES` is set **and**
  `TARGET_PREBUILT_KERNEL` is defined — i.e. exactly this configuration.
- `bootable_recovery/0004` — `android.hardware.gatekeeper-V1-ndk` added to both
  `Android.mk` and `libtar/Android.mk`, needed by the AIDL gatekeeper port below.
- `bootable_recovery/0005` — the `libtar/append.c` buffer overflow described above, hit
  during a real Data backup.
- `system_vold/0001` — the `cp_needsCheckpoint()` hang described above.
- `system_vold/0002` — the HIDL→AIDL gatekeeper port described above, in
  `Decrypt.cpp` (plus the `android.hardware.gatekeeper-V1-ndk` dependency in
  `Android.bp` — the matching `bootable_recovery/` half is `0004` above).

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

The same staleness applies to anything `BOARD_RECOVERY_IMAGE_PREPARE` edits or that
`PRODUCT_COPY_FILES` installs. To be sure a change in this tree is really in the image:

```
rm -f out/target/product/oulu/recovery/root/init.recovery.tee.rc \
      out/target/product/oulu/recovery/root/prop.default
mka vendorbootimage
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

Keep the other slot's stock `vendor_boot` intact as a fallback while testing.

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
- **Only `fastboot reboot recovery` reliably reboots this device from TWRP.**
  `adb reboot`, `adb reboot recovery`, `twrp reboot recovery` and
  `setprop sys.powerctl reboot,recovery` all silently do nothing — check `/proc/uptime`
  rather than assuming a reboot happened.
- **There is no `logd` or `logcat` in recovery.** liblog output from HAL processes goes to
  `/dev/pmsg0` and is only readable *after a reboot*, from
  `/sys/fs/pstore/pmsg-ramoops-0`. Records are `tag\0message`, so decode with
  `cat /sys/fs/pstore/pmsg-ramoops-0 | tr '\0' '\n'` and take the line *after* the tag.
  This is the only way to see why a vendor HAL failed.
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
- **`tee_vintf_unused/`** holds the four Trustonic VINTF fragments transcribed from stock.
  They are *not* installed: mounting the real `/vendor` supplies the genuine device
  manifest, which is the correct source. They are kept for reference because an earlier
  approach shipped device-type fragments into `/system/etc/vintf/manifest/`, which broke
  servicemanager's framework-manifest merge — device HAL declarations belong in the
  **vendor** manifest, not the framework one.

## Known issues

- **Battery always shows 100% in TWRP.** `battery_utils.cpp` logs
  `Unable to call getCapacity: EX_UNSUPPORTED_OPERATION` once per second because no AIDL
  `IHealth` HAL is declared in recovery, and falls back to a hardcoded
  `Using fake battery capacity 100.`. This is TWRP's own intentional stub, not something
  this tree introduced — charging state still reports correctly, only the percentage is
  fake. Filter `grep -v battery_utils` when reading `/tmp/recovery.log`; fixing it for
  real means declaring/wiring a real `IHealth` HAL in recovery, the same shape of work as
  the Gatekeeper VINTF fix above.
- `android.hardware.boot.IBootControl/default` is served by nothing in recovery, which is
  why `Checkpoint.cpp` had to stop waiting on it (see the fixes above).
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
