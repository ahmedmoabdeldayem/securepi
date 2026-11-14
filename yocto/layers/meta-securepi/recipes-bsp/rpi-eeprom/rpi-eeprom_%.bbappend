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

        # Read current config from firmware binary and add SIGNED_BOOT=1 + program_pubkey=1.
        # NOTE: do NOT use --bootcode here. That flag embeds the signed bootcode INTO the
        # EEPROM SPI flash binary, changing the BOOTSYS section size and breaking the
        # BCM2712 ROM's own Raspberry Pi signature verification. The customer-signed bootcode
        # goes in boot.img (FAT partition) instead: see securepi-bootimg recipe.
        ${PYTHON} "${S}/rpi-eeprom-config" "${FW}" > "${WORKDIR}/bootconf.txt"
        grep -q "^SIGNED_BOOT" "${WORKDIR}/bootconf.txt" || echo "SIGNED_BOOT=1" >> "${WORKDIR}/bootconf.txt"
        grep -q "^program_pubkey" "${WORKDIR}/bootconf.txt" || echo "program_pubkey=1" >> "${WORKDIR}/bootconf.txt"

        # Sign the config file: produces a .sig with SHA256 hash + RSA signature
        "${S}/rpi-eeprom-digest" -k "${KEY}" -i "${WORKDIR}/bootconf.txt" -o "${WORKDIR}/bootconf.sig"

        # Create signed binary: config + pubkey embedded, no bootcode modification
        SIGNED_TMP="${WORKDIR}/$(basename ${FW%.bin})-signed.bin"
        ${PYTHON} "${S}/rpi-eeprom-config" \
            --config "${WORKDIR}/bootconf.txt" \
            --digest "${WORKDIR}/bootconf.sig" \
            --pubkey "${WORKDIR}/eeprom-pubkey.pem" \
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

do_deploy() {
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
    fi
    RECOVERY="${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/recovery.bin"
    [ -f "${RECOVERY}" ] && install -m 0644 "${RECOVERY}" "${DEPLOYDIR}/recovery.bin"

    # Deploy customer-signed bootcode.bin for the FAT partition (goes inside boot.img).
    # program_pubkey=1 in the EEPROM config triggers OTP burning only after the EEPROM
    # verifies a customer-signed bootcode in the FAT partition at runtime.
    # The signed bootcode appends: length(4B LE) + keynum(4B LE) + version(4B LE) +
    # RSA_sig(256B) + pubkey(264B) after the original bootcode bytes, so the BCM2712
    # can still use it as a secondary bootloader while also verifying the customer sig.
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
                        -o "${DEPLOYDIR}/bootcode.bin"
                    bbnote "Customer-signed bootcode deployed for FAT partition: $(ls -lh ${DEPLOYDIR}/bootcode.bin | awk '{print \$5}')"
                fi
            fi
        fi
    fi
}

addtask do_deploy after do_sign_eeprom before do_build
