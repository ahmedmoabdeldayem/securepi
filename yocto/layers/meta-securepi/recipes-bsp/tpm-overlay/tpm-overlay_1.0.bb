SUMMARY = "TPM SLB9670 device tree overlay from RPi firmware"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# The 6.12 RPi kernel does not build tpm-slb9670.dtbo (not in overlays/Makefile).
# The dtbo is sourced from the RPi firmware package (rpi-bootfiles 20250430).
SRC_URI = "file://tpm-slb9670.dtbo"

S = "${WORKDIR}"

inherit deploy nopackages

do_deploy() {
    install -m 0644 ${WORKDIR}/tpm-slb9670.dtbo ${DEPLOYDIR}/tpm-slb9670.dtbo
}

addtask deploy after do_install before do_build
