SUMMARY = "U-Boot boot script for SecurePi that loads u-boot.dtb for FIT signature enforcement"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "u-boot-mkimage-native"
INHIBIT_DEFAULT_DEPS = "1"

BOOT_MEDIA ?= "mmc"

do_compile() {
    cat > ${WORKDIR}/boot.cmd << 'BOOTEOF'
fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs
fatload @@BOOT_MEDIA@@ 0:1 ${fdt_addr_r} u-boot.dtb
fdt addr -c ${fdt_addr_r}
fatload @@BOOT_MEDIA@@ 0:1 ${kernel_addr_r} fitImage
if test ! -e @@BOOT_MEDIA@@ 0:1 uboot.env; then saveenv; fi;
bootm ${kernel_addr_r} - ${fdt_addr}
BOOTEOF
    sed -i "s/@@BOOT_MEDIA@@/${BOOT_MEDIA}/g" ${WORKDIR}/boot.cmd
    mkimage -A ${UBOOT_ARCH} -T script -C none -n "Boot script" -d ${WORKDIR}/boot.cmd boot.scr
}

inherit kernel-arch deploy nopackages

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 boot.scr ${DEPLOYDIR}
}

addtask do_deploy after do_compile before do_build

PROVIDES += "u-boot-default-script"
