# Sign EEPROM firmware during the Yocto build.
# Mirrors the UBOOT_SIGN_ENABLE pattern for FIT images.
#
# Variables (set in securepi.conf):
#   EEPROM_SIGN_ENABLE  = "1"
#   EEPROM_SIGN_KEYDIR  = path to keys/bootloader-signing/
#   EEPROM_SIGN_KEYNAME = filename without extension
#
# The .key file is git-ignored and must be present on the build host before
# building (see the README).
#
# Output: for each pieeprom-*.bin in the default/ firmware directory,
# a signed pieeprom-*-signed.bin is placed alongside it and packaged
# into the rpi-eeprom image package.

EEPROM_SIGN_ENABLE ?= "0"
EEPROM_SIGN_KEYDIR ?= ""
EEPROM_SIGN_KEYNAME ?= ""

inherit python3native

do_sign_eeprom[depends] += " \
    openssl-native:do_populate_sysroot \
    python3-pycryptodomex-native:do_populate_sysroot \
"

# Re-run when the signing key file content changes (key swap for OTP verification test).
# The suffix must be :True. Bitbake's checksum.py silently skips entries ending in :False
# (it means "file did not exist at parse time"), which made key swaps invisible to sstate.
# The .crt is tracked too: the embedded public key is extracted from it.
do_sign_eeprom[file-checksums] += " \
    ${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key:True \
    ${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.crt:True \
"

# fakeroot is required so that install -m 0644 runs under pseudo.
# Without it the signed files land in ${D} with the build user's uid,
# and sstatesig.py (which runs outside pseudo) raises a KeyError when
# it can't map that uid to a user in the target rootfs.
fakeroot do_sign_eeprom() {
    if [ "${EEPROM_SIGN_ENABLE}" != "1" ]; then
        bbdebug 1 "EEPROM_SIGN_ENABLE not set: skipping EEPROM signing"
        return 0
    fi

    KEY="${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key"
    CRT="${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.crt"

    if [ ! -f "${KEY}" ]; then
        bbwarn "EEPROM signing key not found at ${KEY}, skipping EEPROM signing"
        return 0
    fi

    # rpi-eeprom-digest needs xxd to hex-encode the RSA signature.
    # Avoid a vim-native dependency by implementing only the -p (plain hex) mode.
    mkdir -p "${WORKDIR}/signing-bin"
    printf '#!/bin/sh\n%s -c "import sys; sys.stdout.write(sys.stdin.buffer.read().hex())" "$@"\n' \
        "${PYTHON}" > "${WORKDIR}/signing-bin/xxd"
    chmod +x "${WORKDIR}/signing-bin/xxd"

    export PATH="${WORKDIR}/signing-bin:${STAGING_BINDIR_NATIVE}:${PATH}"

    # Extract RSA public key from the certificate
    openssl x509 -in "${CRT}" -noout -pubkey > "${WORKDIR}/eeprom-pubkey.pem"

    # Remove any stale -signed.bin files sstate may have restored from a previous
    # build before we start. Without this, the glob below picks them up and
    # produces double-signed (-signed-signed.bin) files.
    rm -f "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/"*-signed.bin
    rm -f "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/latest/"*-signed.bin

    # Sign both default/ and latest/: latest/ has newer firmware (e.g. 2025-03-19)
    # which is needed for pieeprom.upd: the EEPROM silently skips same-version updates,
    # so pieeprom.upd must be NEWER than the currently-running EEPROM firmware.
    for FW in \
        "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/"pieeprom-*.bin \
        "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/latest/"pieeprom-*.bin; do
        [ -f "${FW}" ] || continue

        bbnote "Signing EEPROM firmware: $(basename ${FW})"

        # Counter-sign the EEPROM's embedded bootcode.bin with the customer key.
        # Once OTP holds the customer key hash, the BCM2712 BootROM refuses to run any
        # bootcode in SPI flash that is not signed by Raspberry Pi AND counter-signed by
        # the customer: it halts silently before UART is even initialised.
        # This mirrors usbboot/tools/update-pieeprom.sh -f (the path that produced the
        # working 2026 image). The 2025 images are not A/B capable, so there is no
        # separate bootsys section to sign.
        BCDIR="${WORKDIR}/bootcode-$(basename ${FW%.bin})"
        rm -rf "${BCDIR}" && mkdir -p "${BCDIR}"
        (cd "${BCDIR}" && ${PYTHON} "${S}/rpi-eeprom-config" -x "${FW}")
        ${PYTHON} "${S}/tools/rpi-sign-bootcode" \
            -c 2712 \
            -i "${BCDIR}/bootcode.bin" \
            -k "${KEY}" \
            -n 16 \
            -v 0 \
            -o "${BCDIR}/bootcode.bin.signed"

        # Write the full EEPROM config explicitly rather than patching firmware defaults.
        # Firmware package defaults (e.g. BOOT_ORDER=0xf461, NET_INSTALL_AT_POWER_ON=1)
        # are unsafe to inherit: we own every field here.
        #
        # BOOT_RAMDISK=1: EEPROM always loads boot.img and verifies boot.sig against the
        # OTP-locked customer key BEFORE mounting it as the boot filesystem. Without this
        # the EEPROM falls back to individual FAT files and boot.img RSA check is non-fatal.
        cat > "${WORKDIR}/bootconf.txt" << 'EEPROMCONF'
[all]
BOOT_UART=1
POWER_OFF_ON_HALT=1
BOOT_ORDER=0xf2461
ENABLE_SELF_UPDATE=0
SIGNED_BOOT=1
program_pubkey=1
BOOT_RAMDISK=1
EEPROMCONF

        # Sign the config file: produces a .sig with SHA256 hash + RSA signature
        "${S}/rpi-eeprom-digest" -k "${KEY}" -i "${WORKDIR}/bootconf.txt" -o "${WORKDIR}/bootconf.sig"

        # Create signed binary: config + pubkey + counter-signed bootcode embedded
        SIGNED_TMP="${WORKDIR}/$(basename ${FW%.bin})-signed.bin"
        ${PYTHON} "${S}/rpi-eeprom-config" \
            --config "${WORKDIR}/bootconf.txt" \
            --digest "${WORKDIR}/bootconf.sig" \
            --pubkey "${WORKDIR}/eeprom-pubkey.pem" \
            --bootcode "${BCDIR}/bootcode.bin.signed" \
            --out "${SIGNED_TMP}" \
            "${FW}"
        install -m 0644 "${SIGNED_TMP}" "${FW%.bin}-signed.bin"
    done
}

addtask sign_eeprom after do_install before do_package

# Deploy the latest signed EEPROM bin, recovery.bin, and customer-signed bootcode.bin
# to DEPLOY_DIR_IMAGE so that securepi-bootimg can include them in boot.img.
# In SIGNED_BOOT=1 mode the EEPROM reads everything from boot.img (not the outer FAT),
# so pieeprom.upd must live inside boot.img for EEPROM self-update to work.
# The customer-signed bootcode.bin inside boot.img is what program_pubkey=1 verifies
# before burning the customer key hash to OTP.
inherit deploy

do_deploy[depends] += " \
    python3-pycryptodomex-native:do_populate_sysroot \
"

do_deploy[file-checksums] += "${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key:True"

do_deploy() {
    # rpi-eeprom-digest uses xxd for hex encoding: provide the same shim as do_sign_eeprom.
    mkdir -p "${WORKDIR}/signing-bin"
    printf '#!/bin/sh\n%s -c "import sys; sys.stdout.write(sys.stdin.buffer.read().hex())" "$@"\n' \
        "${PYTHON}" > "${WORKDIR}/signing-bin/xxd"
    chmod +x "${WORKDIR}/signing-bin/xxd"
    export PATH="${WORKDIR}/signing-bin:${STAGING_BINDIR_NATIVE}:${PATH}"

    # Deploy the newest signed EEPROM firmware
    LATEST=""
    for SIGNED in \
        "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/"pieeprom-*-signed.bin \
        "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/latest/"pieeprom-*-signed.bin; do
        [ -f "${SIGNED}" ] && LATEST="${SIGNED}"
    done
    if [ -n "${LATEST}" ]; then
        install -m 0644 "${LATEST}" "${DEPLOYDIR}/pieeprom-signed.bin"
        bbnote "Deployed signed EEPROM to DEPLOYDIR: $(basename ${LATEST})"
        # Generate pieeprom.sig using rpi-eeprom-digest + customer key.
        # The EEPROM bootloader (2025+) requires an RSA-signed digest here, not a
        # plain SHA256. It extracts the customer public key from pieeprom.upd's config
        # section and verifies this signature before applying the self-update.
        if [ "${EEPROM_SIGN_ENABLE}" = "1" ]; then
            KEY="${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key"
            if [ -f "${KEY}" ]; then
                "${S}/rpi-eeprom-digest" \
                    -k "${KEY}" \
                    -i "${DEPLOYDIR}/pieeprom-signed.bin" \
                    -o "${DEPLOYDIR}/pieeprom.sig"
                bbnote "Generated RSA-signed pieeprom.sig with customer key"
            else
                bbwarn "Customer key not found: pieeprom.sig not generated, EEPROM self-update will fail"
            fi
        fi
    fi
    RECOVERY="${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/recovery.bin"
    [ -f "${RECOVERY}" ] && install -m 0644 "${RECOVERY}" "${DEPLOYDIR}/recovery.bin"

    # Deploy customer-signed bootcode.bin for the outer FAT and inside boot.img.
    # The BCM2712 BootROM reads bootcode.bin from the OUTER FAT to verify the customer
    # RSA signature before honoring program_pubkey=1 and burning OTP. It must be the
    # signed version (76 KiB) not the stock unsigned version from rpi-bootfiles (52 KiB).
    # Deployed as bootcode-signed.bin to avoid being overwritten by rpi-bootfiles; the
    # IMAGE_BOOT_FILES:append in securepi.conf then maps it as bootcode.bin in the FAT.
    if [ "${EEPROM_SIGN_ENABLE}" = "1" ]; then
        KEY="${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key"
        if [ -f "${KEY}" ]; then
            # Extract bootcode.bin from a firmware binary (-x writes to CWD)
            FW_SRC=""
            for BDIR in latest default; do
                for FW in "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/${BDIR}/"pieeprom-*.bin; do
                    [ -f "${FW}" ] && FW_SRC="${FW}"
                done
                [ -n "${FW_SRC}" ] && break
            done
            if [ -n "${FW_SRC}" ]; then
                (cd "${WORKDIR}" && ${PYTHON} "${S}/rpi-eeprom-config" -x "${FW_SRC}" 2>/dev/null || true)
                if [ -f "${WORKDIR}/bootcode.bin" ]; then
                    ${PYTHON} "${S}/tools/rpi-sign-bootcode" \
                        -c 2712 \
                        -i "${WORKDIR}/bootcode.bin" \
                        -k "${KEY}" \
                        -n 16 \
                        -v 0 \
                        -o "${DEPLOYDIR}/bootcode-signed.bin"
                    bbnote "Customer-signed bootcode deployed for FAT partition: $(ls -lh ${DEPLOYDIR}/bootcode-signed.bin | awk '{print \$5}')"
                fi
            fi
        fi
    fi

    # rpiboot-update/: used to reflash the EEPROM SPI flash after OTP is already burned.
    # This updates the EEPROM config to include BOOT_RAMDISK=1 so the EEPROM enforces
    # boot.img RSA verification on every boot.
    # config.txt omits program_pubkey because the key hash is already in OTP.
    # Usage: copy rpiboot-update/ to the machine connected to the Pi and run
    # sudo rpiboot -d rpiboot-update
    if [ -f "${DEPLOYDIR}/pieeprom-signed.bin" ] && \
       [ -f "${DEPLOYDIR}/pieeprom.sig" ]; then

        UPDATEDIR="${DEPLOYDIR}/rpiboot-update"
        rm -rf "${UPDATEDIR}"
        mkdir -p "${UPDATEDIR}"

        # bootcode5.bin for rpiboot must be the RECOVERY bootcode (usbboot/secure-boot-recovery5/),
        # NOT the EEPROM-embedded bootcode. These are different binaries:
        # - EEPROM bootcode (76 KiB): embedded in pieeprom.bin, runs the EEPROM bootloader.
        # - Recovery bootcode (96 KiB): served by rpiboot to BCM2712 BootROM in USB recovery
        #   mode; boots the EEPROM update ramdisk. Must be signed with customer key after OTP burn.
        # The recovery bootcode lives in usbboot/rpi-eeprom submodule. Init it if needed.
        USBBOOT="${TOPDIR}/../yocto/layers/usbboot"
        RECOVERY_BIN="${USBBOOT}/rpi-eeprom/firmware-2712/latest/recovery.bin"
        if [ ! -f "${RECOVERY_BIN}" ]; then
            bbnote "Initialising usbboot rpi-eeprom submodule for recovery bootcode"
            (cd "${USBBOOT}" && git submodule update --init rpi-eeprom 2>/dev/null) || true
        fi
        # Counter-sign the UNSIGNED upstream recovery.bin exactly once (update-pieeprom.sh -r).
        # rpi-sign-bootcode appends a signature block, so signing an already-signed file
        # (e.g. usbboot/secure-boot-recovery5/bootcode5.bin) stacks a second signature.
        if [ -f "${RECOVERY_BIN}" ]; then
            KEY="${EEPROM_SIGN_KEYDIR}/${EEPROM_SIGN_KEYNAME}.key"
            if [ -f "${KEY}" ]; then
                ${PYTHON} "${S}/tools/rpi-sign-bootcode" \
                    -c 2712 \
                    -i "${RECOVERY_BIN}" \
                    -k "${KEY}" \
                    -n 16 \
                    -v 0 \
                    -o "${UPDATEDIR}/bootcode5.bin"
                bbnote "Signed recovery bootcode5.bin for rpiboot-update/"
            else
                bbwarn "Customer key not found: rpiboot-update/bootcode5.bin not signed"
            fi
        else
            bbwarn "usbboot recovery.bin not found, run kas checkout kas.yml"
        fi

        install -m 0644 "${DEPLOYDIR}/pieeprom-signed.bin" "${UPDATEDIR}/pieeprom.bin"
        # rpiboot's recovery.bin only needs the plain sha256 + ts digest (same format as
        # usbboot's update-pieeprom.sh). The RSA-signed pieeprom.sig is for self-update.
        "${S}/rpi-eeprom-digest" -i "${UPDATEDIR}/pieeprom.bin" -o "${UPDATEDIR}/pieeprom.sig"
        printf 'uart_2ndstage=1\n' > "${UPDATEDIR}/config.txt"

        # NOTE: do NOT include bootfiles.bin in rpiboot-update/.
        # When bootfiles.bin is present, rpiboot reads bootcode5.bin FROM THE ARCHIVE
        # (the unsigned 68KB version inside bootfiles.bin) instead of the separate
        # customer-signed bootcode5.bin file. The BCM2712 OTP lock then rejects it.
        # EEPROM updates do not need the archive: the BCM2712 handles memory init
        # internally.
        bbnote "Deployed rpiboot-update/ (BOOT_RAMDISK=1) to ${DEPLOYDIR}"
    fi
}

addtask do_deploy after do_sign_eeprom before do_build
