# BoardConfig.mk for motorola oulu (motorola edge 2025 / XT2519-1)
#
# Derived from partition images pulled directly from a running device
# (fingerprint motorola/oulu_g_sys/oulu:16/W1VDS36H.50-38-3-8/d4cc0-c51c67:user/release-keys)
# on 2026-08-27. Values marked TODO should be verified against an actual
# build attempt before relying on them.

DEVICE_PATH := device/motorola/oulu

# Platform
TARGET_BOARD_PLATFORM := mt6878
TARGET_BOOTLOADER_BOARD_NAME := oulu
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic

# Kernel - prebuilt GKI 6.1.141 (android14-11), header_version 4 (boot+vendor_boot split)
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_TAGS_OFFSET := 0x47c80000
BOARD_RAMDISK_OFFSET := 0x66f00000
BOARD_KERNEL_OFFSET := 0x40000000
BOARD_DTB_OFFSET := 0x47c80000
BOARD_KERNEL_CMDLINE :=
BOARD_KERNEL_VENDOR_CMDLINE := bootopt=64S3,32N2,64N2
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
TARGET_USES_MKE2FS := true

# Stock compresses BOTH vendor_boot ramdisk fragments with LZ4 (legacy frame, magic
# 02 21 4c 18); the build default is gzip. The device kernel has CONFIG_RD_GZIP and
# CONFIG_RD_LZ4 so a mixed-compression image would most likely boot, but the repacked
# image keeps the stock LZ4 platform fragment alongside our recovery fragment, so match
# stock rather than rely on that.
BOARD_RAMDISK_USE_LZ4 := true

# This device has no dedicated recovery partition. The stock vendor_boot
# ramdisk table has two fragments:
#   --ramdisk_type 1 --ramdisk_name ''         (platform ramdisk)
#   --ramdisk_type 2 --ramdisk_name recovery   (recovery ramdisk)
# The build system supports this natively (build/make/core/Makefile:337-345):
# BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT appends a "recovery" fragment
# built from TARGET_RECOVERY_ROOT_OUT and passes --ramdisk_type RECOVERY, which
# reproduces the stock layout. Flash the result with `fastboot flash vendor_boot`
# (there is no standalone recovery.img on this device).
BOARD_USES_RECOVERY_AS_BOOT := false
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true

# Partition sizes (bytes), read directly off-device via blockdev --getsize64
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_DTBOIMG_PARTITION_SIZE := 8388608

# Dynamic partitions (virtual A/B - lpdump shows Header flags: virtual_ab_device)
BOARD_SUPER_PARTITION_SIZE := 14495514624
BOARD_SUPER_PARTITION_GROUPS := main
BOARD_MAIN_PARTITION_LIST := system system_ext product vendor vendor_dlkm system_dlkm
BOARD_MAIN_SIZE := 14495514624
BOARD_USES_METADATA_PARTITION := true
BOARD_SUPER_PARTITION_METADATA_DEVICE := super
TW_INCLUDE_LOGICAL := true

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    vendor_boot \
    dtbo \
    vbmeta \
    vbmeta_system \
    system \
    vendor \
    product \
    system_ext \
    vendor_dlkm \
    system_dlkm

# Filesystems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_HAS_NO_REAL_SDCARD := true

# /data is F2FS with fscrypt v2 + inline crypt (see fstab.emmc pulled from device)
#
# TEMPORARILY DISABLED for first bring-up. TWRP's own android-14.1 tree does not
# compile with FBE enabled: bootable/recovery/libtar calls get_policy_size(),
# get_policy_descriptor(), get_policy(), get_policy_content() and
# fscrypt_policy_size(), which are called ONLY in libtar and are defined nowhere
# in the tree - TeamWin's system/vold (android-14.1) exposes a different API
# (lookup_ref_key/fscrypt_policy_get_struct) and vendor/twrp/libfscrypt does not
# provide them either. Verified bootable/recovery is at the exact tip of
# android-14.1 (426b747), so this is an upstream inconsistency, not a sync problem.
# Re-enable these once those helpers exist; without them TWRP cannot decrypt /data.
# TW_INCLUDE_CRYPTO := true
# TW_INCLUDE_CRYPTO_FBE := true
# TW_INCLUDE_FBE_METADATA_DECRYPT := true
# /data uses fscrypt v2 with hardware-wrapped keys. The stock policy string,
# read off the device from /vendor/etc/fstab.mt6878, is
# aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0 and is carried
# verbatim in recovery.fstab - a near-match fails fscrypt policy lookup.
# 2 selects USE_FSCRYPT_POLICY_V2 in libtar/Android.mk (anything but 1 does).
TW_USE_FSCRYPT_POLICY := 2
TW_FORCE_KEYMASTER_VER := true
TW_INCLUDE_LIBRESETPROP := true

# Display - 1220x2712 @450dpi, backlight scale is 0-16181 (not the usual 0-255)
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := /sys/class/leds/lcd-backlight/brightness
TW_MAX_BRIGHTNESS := 16181
TW_DEFAULT_BRIGHTNESS := 8000
TW_NO_SCREEN_BLANK := true

# MTP must stay off. TWRP enables MTP by setting sys.usb.config=mtp,adb, but
# bootable/recovery/etc/init.rc only has configfs triggers for adb, fastboot,
# sideload and none. The none trigger tears the gadget down (UDC "none", rm
# configs/b.1/f1) and nothing matches mtp,adb to rebuild it, so USB dies the
# moment TWRP starts - no adb, no fastboot, nothing enumerates.
TW_EXCLUDE_MTP := true
# Without this, minuitwrp's graphics_drm.cpp falls into its default branch, which
# allocates a 16bpp RGB565 dumb buffer but renders into it via GGL_PIXEL_FORMAT_BGRA_8888
# (32bpp) - painting the splash then runs off the end of the mapping and SIGSEGVs.
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"

# Touchscreen. The panel is Goodix behind Motorola's mmi touch framework; none of
# these ship in the vendor_boot ramdisk, so recovery has no touch until they are
# loaded from vendor_dlkm (which TWRP mounts itself - see recovery.fstab).
# sensors_class.ko and mtk_disp_notify.ko are already in vendor_boot's modules.load.
# Order matters: mmi_relay -> mmi_info -> touchscreen_u_mmi -> goodix_*.
TW_LOAD_VENDOR_MODULES := "mmi_relay.ko mmi_info.ko touchscreen_u_mmi.ko goodix_brl_u_mmi.ko goodix_gt96x_u_mmi.ko"

# AVB
BOARD_AVB_ENABLE := true
TW_INCLUDE_AVB_VERIFICATION := true

# UFS storage - fstab uses legacy "emmc" fs_mgr keyword but /data mount
# options reference sysfs_path=.../112b0000.ufshci, confirming real storage is UFS.
BOARD_SUPPRESS_SECURE_ERASE := true

# Recovery / TWRP
TARGET_RECOVERY_DEVICE_DIRS += $(DEVICE_PATH)
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

# SELinux. Stock policy confines the recovery domain far too tightly for TWRP:
# it is denied write on rootfs (so it cannot create /etc/additional.fstab and then
# aborts in fgets), property_service set for twrp.*, dm_device ioctl (logical
# partitions) and system_dlkm getattr. Making the recovery domain permissive is
# scoped to recovery only - normal Android loads its policy from the stock system
# and vendor partitions, which this tree never builds or flashes.
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_REPACKTOOLS := true
TW_DEFAULT_LANGUAGE := en
RECOVERY_VARIANT := twrp

# Root: stock init_boot ramdisk on this device is already KernelSU-patched
# (init.real backup + kernelsu.ko present) - informational only, does not
# affect the TWRP build.
