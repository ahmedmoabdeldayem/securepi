FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://mount-copybind"

do_install:append() {
    install -m 0755 ${WORKDIR}/mount-copybind ${D}${base_sbindir}/mount-copybind
}
