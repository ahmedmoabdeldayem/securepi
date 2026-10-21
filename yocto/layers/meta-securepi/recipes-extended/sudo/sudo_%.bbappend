FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://securepi-sudo"

do_install:append() {
    install -m 0440 ${WORKDIR}/securepi-sudo ${D}${sysconfdir}/sudoers.d/securepi
}
