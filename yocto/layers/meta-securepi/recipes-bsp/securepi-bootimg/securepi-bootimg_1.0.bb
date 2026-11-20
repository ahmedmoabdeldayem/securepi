# Creates and signs boot.img: the FAT32 boot archive required by the RPi5
# EEPROM when SIGNED_BOOT=1 is active. In secure-boot mode the EEPROM loads
# boot.img instead of individual files (kernel_2712.img, DTBs, etc.).
#
# The EEPROM expects boot.img to be a raw FAT32 filesystem image (not squashfs,
# not a disk image with an MBR, just a FAT32 filesystem with the BPB at byte 0).
#
# Variables (set in securepi.conf):
#   BOOT_IMG_SIGN_ENABLE  = "1"
#   BOOT_IMG_SIGN_KEYDIR  = path to keys/bootloader-signing/
#   BOOT_IMG_SIGN_KEYNAME = filename without extension
#
# The .key file is git-ignored and must be present on the build host.
#
# Signature format (rpi-eeprom-digest compatible):
#   <sha256hex>\nts: <timestamp>\nrsa2048: <rsahex>\n

SUMMARY = "Signed FAT32 boot image for RPi5 EEPROM secure boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

BOOT_IMG_SIGN_ENABLE ?= "0"
BOOT_IMG_SIGN_KEYDIR ?= ""
BOOT_IMG_SIGN_KEYNAME ?= ""

inherit deploy

do_deploy[depends] += " \
    dosfstools-native:do_populate_sysroot \
    mtools-native:do_populate_sysroot \
    openssl-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    u-boot:do_deploy \
    rpi-bootfiles:do_deploy \
    securepi-u-boot-scr:do_deploy \
    tpm-overlay:do_deploy \
    rpi-eeprom:do_deploy \
    ${@'${DM_VERITY_IMAGE}:do_image_${DM_VERITY_IMAGE_TYPE}' if d.getVar('DM_VERITY_IMAGE') else ''} \
"

# Block device holding the verity data + hash tree (rootfs partition in securepi.wks.in)
VERITY_ROOT_DEV ?= "/dev/mmcblk0p2"

# Re-run do_deploy when the signing key file content changes.
# Without this, swapping keys/bootloader-signing/ and rebuilding would reuse
# the cached boot.img and boot.sig signed by the previous key.
# Must be :True. Bitbake skips :False entries entirely (see rpi-eeprom_%.bbappend).
do_deploy[file-checksums] += "${BOOT_IMG_SIGN_KEYDIR}/${BOOT_IMG_SIGN_KEYNAME}.key:True"

do_deploy() {
    if [ "${BOOT_IMG_SIGN_ENABLE}" != "1" ]; then
        bbdebug 1 "BOOT_IMG_SIGN_ENABLE not set: skipping boot.img creation"
        return 0
    fi

    KEY="${BOOT_IMG_SIGN_KEYDIR}/${BOOT_IMG_SIGN_KEYNAME}.key"
    if [ ! -f "${KEY}" ]; then
        bbwarn "boot.img signing key not found at ${KEY}, skipping boot.img creation"
        return 0
    fi

    DEPLOY="${DEPLOY_DIR_IMAGE}"
    STAGE="${WORKDIR}/boot-stage"
    rm -rf "${STAGE}"
    mkdir -p "${STAGE}/overlays"

    # RPi firmware blobs and board config from rpi-bootfiles
    cp "${DEPLOY}/bootfiles/config.txt" "${STAGE}/"
    cp "${DEPLOY}/bootfiles/cmdline.txt" "${STAGE}/" 2>/dev/null || true

    # dm-verity: replace the plain root= with a verity device the kernel creates
    # itself (CONFIG_DM_INIT). The table carries the root hash, so the rootfs is
    # now covered by this boot.img's signature and by its PCR 8 measurement.
    if [ -n "${DM_VERITY_IMAGE}" ]; then
        ENV="${STAGING_VERITY_DIR}/${DM_VERITY_IMAGE}.${DM_VERITY_IMAGE_TYPE}.verity.env"
        [ -f "${ENV}" ] || bbfatal "dm-verity env ${ENV} missing: image not built with dm-verity-img?"
        v() { sed -n "s/^$1=//p" "${ENV}"; }

        DATA_BLOCKS=$(v DATA_BLOCKS)
        DATA_BS=$(v DATA_BLOCK_SIZE)
        HASH_BS=$(v HASH_BLOCK_SIZE)
        DATA_SIZE=$(v DATA_SIZE)
        ROOT_HASH=$(v ROOT_HASH)
        SALT=$(v SALT)
        for X in "$DATA_BLOCKS" "$DATA_BS" "$HASH_BS" "$DATA_SIZE" "$ROOT_HASH" "$SALT"; do
            [ -n "$X" ] || bbfatal "incomplete dm-verity env ${ENV}"
        done

        SECTORS=$(expr ${DATA_BLOCKS} \* ${DATA_BS} / 512)
        # The class runs veritysetup with --hash-offset=DATA_SIZE, which writes a
        # one-block verity superblock there; the hash tree starts after it.
        HASH_START=$(expr ${DATA_SIZE} / ${HASH_BS} + 1)
        # No corruption-mode flag: a tampered block returns EIO to the reader
        # (dmesg: "dm-verity ... data block N is corrupted").
        TABLE="0 ${SECTORS} verity 1 ${VERITY_ROOT_DEV} ${VERITY_ROOT_DEV} ${DATA_BS} ${HASH_BS} ${DATA_BLOCKS} ${HASH_START} $(v HASH_ALGORITHM) ${ROOT_HASH} ${SALT}"

        grep -q "root=${VERITY_ROOT_DEV}" "${STAGE}/cmdline.txt" || \
            bbfatal "cmdline.txt has no root=${VERITY_ROOT_DEV} to replace"
        sed -i "s#root=${VERITY_ROOT_DEV}#dm-mod.create=\"vroot,,,ro,${TABLE}\" dm-mod.waitfor=${VERITY_ROOT_DEV} root=/dev/dm-0 ro#" \
            "${STAGE}/cmdline.txt"
        bbnote "dm-verity root hash ${ROOT_HASH}"
        bbnote "cmdline.txt: $(cat ${STAGE}/cmdline.txt)"
    fi
    # Use customer-signed bootcode.bin if available (from rpi-eeprom:do_deploy).
    # program_pubkey=1 in the EEPROM config triggers OTP burning only after verifying
    # this signed bootcode on the FAT partition. Falls back to unsigned for non-secure builds.
    if [ -f "${DEPLOY}/bootcode.bin" ]; then
        cp "${DEPLOY}/bootcode.bin" "${STAGE}/bootcode.bin"
    else
        cp "${DEPLOY}/bootfiles/bootcode.bin" "${STAGE}/bootcode.bin" 2>/dev/null || true
    fi
    for F in "${DEPLOY}"/bootfiles/start*.elf; do
        [ -f "${F}" ] && cp "${F}" "${STAGE}/"
    done
    for F in "${DEPLOY}"/bootfiles/fixup*.dat; do
        [ -f "${F}" ] && cp "${F}" "${STAGE}/"
    done

    # U-Boot binary (EEPROM looks for kernel_2712.img by default on RPi5)
    cp "${DEPLOY}/u-boot.bin" "${STAGE}/kernel_2712.img"

    # U-Boot device tree with embedded FIT signing public key
    cp "${DEPLOY}/u-boot.dtb" "${STAGE}/u-boot.dtb"

    # Signed FIT image (kernel + DTB bundle, verified by U-Boot)
    cp "${DEPLOY}/fitImage" "${STAGE}/fitImage"

    # U-Boot boot script
    cp "${DEPLOY}/boot.scr" "${STAGE}/boot.scr"

    # Board DTBs: only the essential RPi5 B board DTB.
    # CM5 variants and versioned timestamped copies are excluded: each long filename
    # consumes 7-8 FAT directory entries, pushing pieeprom.upd beyond the EEPROM's
    # FAT directory scan limit (~80 entries / 5 clusters of 512 bytes each).
    [ -f "${DEPLOY}/bcm2712-rpi-5-b.dtb" ] && cp "${DEPLOY}/bcm2712-rpi-5-b.dtb" "${STAGE}/"
    [ -f "${DEPLOY}/bcm2712-rpi-cm5-cm4io.dtb" ] && cp "${DEPLOY}/bcm2712-rpi-cm5-cm4io.dtb" "${STAGE}/"

    # Overlays (all .dtbo files in deploy root)
    for F in "${DEPLOY}"/*.dtbo; do
        [ -f "${F}" ] && cp "${F}" "${STAGE}/overlays/"
    done

    # Calculate image size: total content + 30% overhead + 2MB for FAT structures
    TOTAL_KB=$(du -sk "${STAGE}" | cut -f1)
    IMG_KB=$(expr $(expr ${TOTAL_KB} \* 130 / 100) + 2048)

    # Create raw FAT32 image (BPB at byte 0, the EEPROM reads FAT directly, no MBR)
    rm -f "${WORKDIR}/boot.img"
    mkdosfs -F 32 -n "boot" -C "${WORKDIR}/boot.img" ${IMG_KB}

    export MTOOLS_SKIP_CHECK=1
    mmd -i "${WORKDIR}/boot.img" ::overlays

    # Copy EEPROM update FIRST: must be in early FAT directory entries (cluster 0-1)
    # so the EEPROM's ramdisk FAT scanner finds it before its scan limit is reached
    if [ -f "${DEPLOY}/pieeprom-signed.bin" ]; then
        mcopy -i "${WORKDIR}/boot.img" "${DEPLOY}/pieeprom-signed.bin" "::/pieeprom.upd"
        [ -f "${DEPLOY}/recovery.bin" ] && mcopy -i "${WORKDIR}/boot.img" "${DEPLOY}/recovery.bin" "::/recovery.bin"
        bbnote "Included pieeprom.upd as first FAT entry in boot.img"
    else
        bbwarn "pieeprom-signed.bin not found: EEPROM will not auto-update from boot.img"
    fi

    # Copy remaining boot files
    for F in "${STAGE}"/*; do
        [ -f "${F}" ] && mcopy -i "${WORKDIR}/boot.img" "${F}" "::/$(basename ${F})"
    done
    for F in "${STAGE}"/overlays/*; do
        [ -f "${F}" ] && mcopy -i "${WORKDIR}/boot.img" "${F}" "::overlays/$(basename ${F})"
    done

    # Sign: format is sha256hex\nts: <ts>\nrsa2048: <hexsig>\n
    # This matches what rpi-eeprom-digest produces.
    SHA256=$(sha256sum "${WORKDIR}/boot.img" | awk '{print $1}')
    TIMESTAMP=$(date +%s)
    RSA_HEX=$(openssl dgst -sign "${KEY}" -sha256 "${WORKDIR}/boot.img" | \
        python3 -c "import sys; sys.stdout.write(sys.stdin.buffer.read().hex())")
    printf '%s\nts: %s\nrsa2048: %s\n' \
        "${SHA256}" "${TIMESTAMP}" "${RSA_HEX}" > "${WORKDIR}/boot.img.sig"

    install -m 0644 "${WORKDIR}/boot.img"     "${DEPLOYDIR}/boot.img"
    install -m 0644 "${WORKDIR}/boot.img.sig" "${DEPLOYDIR}/boot.sig"
    bbnote "boot.img (FAT32) signed and deployed: $(ls -lh ${DEPLOYDIR}/boot.img | awk '{print $5}')"
}

addtask deploy after do_configure before do_build
