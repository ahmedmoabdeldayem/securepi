SUMMARY = "TPM2-backed LUKS auto-unlock service for securedata partition"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://tpm-luks-unlock.sh \
           file://tpm-luks-unlock.service"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tpm-luks-unlock.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "tpm2-tools cryptsetup"

do_install() {
    install -d ${D}${libdir}/securepi
    install -m 0750 ${WORKDIR}/tpm-luks-unlock.sh ${D}${libdir}/securepi/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tpm-luks-unlock.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${libdir}/securepi/tpm-luks-unlock.sh \
               ${systemd_system_unitdir}/tpm-luks-unlock.service"
