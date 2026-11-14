# rpi-bootfiles only deploys .elf/.dat/.bin firmware files.
# The RPi firmware overlays (.dtbo) in ${S}/boot/overlays/ are not deployed,
# so IMAGE_BOOT_FILES references like "overlays/tpm-slb9670.dtbo" fail.
# Deploy all firmware overlays to ${DEPLOYDIR}/overlays/ so they're available
# for WIC image assembly.
do_deploy:append() {
    if [ -d "${S}/boot/overlays" ]; then
        install -d ${DEPLOYDIR}/overlays
        for f in ${S}/boot/overlays/*.dtbo ${S}/boot/overlays/*.dtb; do
            [ -f "$f" ] && install -m 0644 "$f" ${DEPLOYDIR}/overlays/
        done
    fi
}
