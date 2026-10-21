SUMMARY = "Runtime kernel hardening via sysctl"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://99-securepi.conf"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/sysctl.d
    install -m 0644 ${WORKDIR}/99-securepi.conf ${D}${sysconfdir}/sysctl.d/99-securepi.conf
}
