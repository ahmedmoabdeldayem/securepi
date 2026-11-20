SUMMARY = "Measure firmware-verified boot state into TPM PCR 8"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://tpm-measure-boot.sh \
           file://tpm-measure-boot.service"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tpm-measure-boot.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "tpm2-tools"

do_install() {
    install -d ${D}${libdir}/securepi
    install -m 0750 ${WORKDIR}/tpm-measure-boot.sh ${D}${libdir}/securepi/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tpm-measure-boot.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${libdir}/securepi/tpm-measure-boot.sh \
               ${systemd_system_unitdir}/tpm-measure-boot.service"
