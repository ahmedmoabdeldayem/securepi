# Kernel configuration hardening for Raspberry Pi 5
# Applied as a fragment on top of the BSP defconfig.
# a later stage populates the .cfg file: see files/securepi-hardening.cfg

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Uncomment when the config fragment exists
# SRC_URI:append = " file://securepi-hardening.cfg"
