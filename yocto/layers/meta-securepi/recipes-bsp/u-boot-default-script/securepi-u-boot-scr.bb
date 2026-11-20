SUMMARY = "U-Boot boot script for SecurePi that loads u-boot.dtb for FIT signature enforcement"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "u-boot-mkimage-native"
INHIBIT_DEFAULT_DEPS = "1"

BOOT_MEDIA ?= "mmc"

# Where u-boot.dtb (the control FDT holding the FIT public key) is loaded.
# NOT ${fdt_addr_r} (0x02600000): bootm unpacks the ~30 MB kernel Image to
# UBOOT_LOADADDRESS 0x02000000, which runs over 0x02600000 and corrupts the
# control FDT: U-Boot then crashes in fdt_next_tag ("Synchronous Abort").
# 0x08000000 (128 MB) is above the unpacked kernel and below the firmware DT.
UBOOT_CTRL_DTB_ADDR ?= "0x08000000"

do_compile() {
    cat > ${WORKDIR}/boot.cmd << 'BOOTEOF'
fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs
fatload @@BOOT_MEDIA@@ 0:1 @@CTRL_DTB@@ u-boot.dtb
fdt addr -c @@CTRL_DTB@@
fatload @@BOOT_MEDIA@@ 0:1 ${kernel_addr_r} fitImage
if test ! -e @@BOOT_MEDIA@@ 0:1 uboot.env; then saveenv; fi;
bootm ${kernel_addr_r} - ${fdt_addr}
BOOTEOF
    sed -i -e "s/@@BOOT_MEDIA@@/${BOOT_MEDIA}/g" -e "s/@@CTRL_DTB@@/${UBOOT_CTRL_DTB_ADDR}/g" ${WORKDIR}/boot.cmd
    mkimage -A ${UBOOT_ARCH} -T script -C none -n "Boot script" -d ${WORKDIR}/boot.cmd boot.scr
}

inherit kernel-arch deploy nopackages

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 boot.scr ${DEPLOYDIR}
}

addtask do_deploy after do_compile before do_build

PROVIDES += "u-boot-default-script"
