LOCAL_PATH := device/motorola/oulu

# NOTE: do not PRODUCT_COPY_FILES recovery.fstab into $(TARGET_COPY_OUT_RECOVERY)/root/etc.
# TWRP already installs it from TARGET_RECOVERY_FSTAB (set in BoardConfig.mk) to
# recovery/root/system/etc/recovery.fstab. Copying it to root/etc additionally creates
# recovery/root/etc as a real directory, which breaks the ramdisk_files rsync step -
# that step needs to place root/etc as a symlink to /system/etc and cannot replace a
# non-empty directory ("could not make way for new symlink: root/etc").

PRODUCT_PACKAGES += \
    twrp

# Boot control / A/B
PRODUCT_PACKAGES += \
    bootctl

# Kernel modules needed at boot for the storage stack, if any get added
# post-sync from kernel/ (populate once kernel tree finishes syncing).

# First-stage init imports /init.recovery.$(ro.hardware).rc, which is
# init.recovery.mt6878.rc here. It lives in the STOCK recovery ramdisk fragment, so
# replacing that fragment with TWRP's drops it: sys.usb.controller is then never set
# (no adb, no USB enumeration at all) and mtk_plpath_utils never runs, so the
# /dev/block/by-name/* paths recovery.fstab depends on are never created.
# init.recovery.project.rc is a 0-byte stub on this device and exists only so the
# import at the top of init.recovery.mt6878.rc resolves.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6878.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6878.rc \
    $(LOCAL_PATH)/recovery/root/init.recovery.project.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.project.rc

$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
