FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://securepi-fit-signature.cfg"

# Embed the FIT signing public key into U-Boot's device tree at build time.
# U-Boot uses this to verify the FIT image signature on every boot.
UBOOT_SIGN_ENABLE = "1"
UBOOT_SIGN_KEYDIR = "${TOPDIR}/../keys/fit-signing"
UBOOT_SIGN_KEYNAME = "securepi-fit-key"
