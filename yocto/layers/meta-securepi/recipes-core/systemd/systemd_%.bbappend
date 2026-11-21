FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Drop-in to make systemd-rfkill start after var-volatile-lib.service (from
# volatile-binds) has made /var/lib writable. Without this, rfkill races the
# bind mount at boot and fails to create /var/lib/systemd/rfkill/.
SRC_URI:append = " file://rfkill-after-volatile-binds.conf"

do_install:append() {
    install -d ${D}${systemd_unitdir}/system/systemd-rfkill.service.d
    install -m 0644 ${WORKDIR}/rfkill-after-volatile-binds.conf \
        ${D}${systemd_unitdir}/system/systemd-rfkill.service.d/rfkill-after-volatile-binds.conf
}
