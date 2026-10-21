FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://10-seccomp.conf"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}/sshd.service.d
    install -m 0644 ${WORKDIR}/10-seccomp.conf \
        ${D}${systemd_system_unitdir}/sshd.service.d/10-seccomp.conf
}

FILES:${PN}-sshd += "${systemd_system_unitdir}/sshd.service.d/10-seccomp.conf"
