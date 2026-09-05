# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)

# Inherit from oulu device
$(call inherit-product, device/motorola/oulu/device.mk)

PRODUCT_NAME := twrp_oulu
PRODUCT_DEVICE := oulu
PRODUCT_BRAND := motorola
PRODUCT_MODEL := motorola edge 2025
PRODUCT_MANUFACTURER := motorola

PRODUCT_GMS_CLIENTID_BASE := android-motorola

PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=oulu \
    PRODUCT_NAME=oulu_g_sys
