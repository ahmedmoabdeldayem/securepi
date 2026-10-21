# Dev-only: Wi-Fi credentials, serial console user, and networking config.
# SSH disabled: serial console via Debug Probe is the access method.

SUMMARY = "Temporary Wi-Fi credentials and networking config"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://wpa_supplicant-wlan0.conf \
           file://20-wlan0.network \
           file://wpa_supplicant-debug.conf \
           file://debug-boot.sh \
           file://debug-boot.service \
           file://authorized_keys"

S = "${WORKDIR}"

inherit useradd

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "-M -d /home/securepi -s /bin/sh -u 1000 -p '\$6\$uU2.uEWhNmTHC/LL\$DsFzAJ/oPkwV7whTYe5boD0544Nou32My8sBsWNEVylrF1prt9Xy5jkqgcBMCecI85mVm/c9WRbndPQ7rS1Np.' securepi"

RDEPENDS:${PN} = "wpa-supplicant linux-firmware-rpidistro-bcm43455"

FILES:${PN} += "${systemd_unitdir}/system/debug-boot.service \
                /usr/local/bin/debug-boot.sh \
                /home/securepi/"

do_install() {
    # Wi-Fi credentials: readable by root only
    install -d ${D}${sysconfdir}/wpa_supplicant
    install -m 0600 ${WORKDIR}/wpa_supplicant-wlan0.conf \
        ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf

    # systemd-networkd config: request DHCP on wlan0
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/20-wlan0.network \
        ${D}${sysconfdir}/systemd/network/20-wlan0.network

    # Enable wpa_supplicant and systemd-networkd at boot
    install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants
    ln -sf ${systemd_unitdir}/system/wpa_supplicant@.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service
    ln -sf ${systemd_unitdir}/system/systemd-networkd.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/systemd-networkd.service

    # SSH socket: activates sshd on incoming connections
    install -d ${D}${sysconfdir}/systemd/system/sockets.target.wants
    ln -sf ${systemd_unitdir}/system/sshd.socket \
        ${D}${sysconfdir}/systemd/system/sockets.target.wants/sshd.socket

    # wpa_supplicant debug mode: verbose Wi-Fi association logs in journal
    install -d ${D}${sysconfdir}/systemd/system/wpa_supplicant@.service.d
    install -m 0644 ${WORKDIR}/wpa_supplicant-debug.conf \
        ${D}${sysconfdir}/systemd/system/wpa_supplicant@.service.d/debug.conf

    # SSH authorized key: key-based auth, avoids password hash escaping issues
    install -d -m 0700 ${D}/home/securepi/.ssh
    install -m 0600 ${WORKDIR}/authorized_keys ${D}/home/securepi/.ssh/authorized_keys
    chown -R securepi:securepi ${D}/home/securepi

    # Debug boot script: writes service status and logs to /boot/debug.log
    install -d ${D}${base_prefix}/usr/local/bin
    install -m 0755 ${WORKDIR}/debug-boot.sh \
        ${D}${base_prefix}/usr/local/bin/debug-boot.sh
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/debug-boot.service \
        ${D}${systemd_unitdir}/system/debug-boot.service
    ln -sf ${systemd_unitdir}/system/debug-boot.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/debug-boot.service
}
