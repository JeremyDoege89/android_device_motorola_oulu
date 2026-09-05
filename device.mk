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

$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
