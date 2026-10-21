FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# BUSYBOX_SPLIT_SUID=0 prevents BusyBox from creating /usr/bin/busybox.suid
# The .cfg fragment alone is insufficient: this variable controls the install step
BUSYBOX_SPLIT_SUID = "0"

SRC_URI:append = " file://suid-disable.cfg file://10-sandbox.conf"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}/busybox-syslog.service.d
    install -m 0644 ${WORKDIR}/10-sandbox.conf \
        ${D}${systemd_system_unitdir}/busybox-syslog.service.d/10-sandbox.conf
}

FILES:${PN}-syslog += "${systemd_system_unitdir}/busybox-syslog.service.d/10-sandbox.conf"
