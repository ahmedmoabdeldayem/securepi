SUMMARY = "Reset the TPM and measure firmware-verified boot state into PCR 8"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://tpm-measure-boot.sh \
           file://tpm-measure-boot.service \
           file://tpm-reset.sh \
           file://tpm-reset.service"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tpm-reset.service tpm-measure-boot.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# raspi-utils: pinctrl drives the TPM RST# GPIO
# policycoreutils-setfiles: restorecon relabels the re-created /dev/tpm* nodes
# tpm2-tss: its tpm-udev.rules tags /dev/tpm* for systemd. Without it
#   dev-tpm0.device never appears and tpm-reset.service times out after 90 s.
#   (Was only pulled in by tpm2-abrmd before that was removed.)
RDEPENDS:${PN} = "tpm2-tools tpm2-tss raspi-utils policycoreutils-setfiles"

do_install() {
    install -d ${D}${libdir}/securepi
    install -m 0750 ${WORKDIR}/tpm-measure-boot.sh ${D}${libdir}/securepi/
    install -m 0750 ${WORKDIR}/tpm-reset.sh ${D}${libdir}/securepi/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tpm-measure-boot.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/tpm-reset.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${libdir}/securepi/tpm-measure-boot.sh \
               ${libdir}/securepi/tpm-reset.sh \
               ${systemd_system_unitdir}/tpm-measure-boot.service \
               ${systemd_system_unitdir}/tpm-reset.service"
