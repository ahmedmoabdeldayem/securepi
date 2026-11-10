# Kernel configuration hardening for Raspberry Pi 5
# Applied as a fragment on top of the BSP defconfig.
# a later stage populates the .cfg file: see files/securepi-hardening.cfg

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://securepi-hardening.cfg"
SRC_URI:append = " file://tpm-slb9670.dts"

# Build the TPM overlay using the kernel's own dtc so versions always match.
# The dtbo lands in DEPLOYDIR/overlays/ which IMAGE_BOOT_FILES picks up for
# the boot partition via meta-raspberrypi's rpi-default-settings.inc.
do_compile:append() {
    ${STAGING_BINDIR_NATIVE}/dtc -I dts -O dtb -@ \
        ${WORKDIR}/tpm-slb9670.dts \
        -o ${WORKDIR}/tpm-slb9670.dtbo
}

do_deploy:append() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${WORKDIR}/tpm-slb9670.dtbo ${DEPLOYDIR}/overlays/tpm-slb9670.dtbo
}

DEPENDS:append = " dtc-native"

