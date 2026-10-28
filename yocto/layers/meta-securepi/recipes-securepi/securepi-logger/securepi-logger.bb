SUMMARY = "SecurePi telemetry logger, an SELinux-confined example service"
DESCRIPTION = "Minimal compiled service that reads a config, samples /proc/uptime, \
and appends to a log file. Runs in its own minimal SELinux domain (securepi_logger_t)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://securepi-logger.c \
           file://securepi-logger.service \
           file://securepi-logger.conf \
          "

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "securepi-logger.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o securepi-logger securepi-logger.c
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 securepi-logger ${D}${bindir}/securepi-logger

    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/securepi-logger.conf ${D}${sysconfdir}/securepi-logger.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/securepi-logger.service \
        ${D}${systemd_system_unitdir}/securepi-logger.service
}
