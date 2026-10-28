SUMMARY = "SecurePi custom SELinux policy module"
DESCRIPTION = "Confines securepi-specific services with a minimal allow policy \
derived from the first-boot AVC denial log."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://securepi.te \
           file://securepi.fc \
           file://securepi.if \
          "

S = "${WORKDIR}"

DEPENDS = "checkpolicy-native semodule-utils-native"

# Module loading is handled by ROOTFS_POSTPROCESS_COMMAND in securepi-image.bb,
# which runs after all packages are installed and before setfiles labels the rootfs.

do_compile() {
    checkmodule -M -m -o securepi.mod securepi.te
    semodule_package -o securepi.pp -m securepi.mod -f securepi.fc
}

do_install() {
    install -d ${D}${datadir}/selinux/targeted
    install -m 0644 securepi.pp ${D}${datadir}/selinux/targeted/
}

FILES:${PN} = "${datadir}/selinux/targeted/securepi.pp"
