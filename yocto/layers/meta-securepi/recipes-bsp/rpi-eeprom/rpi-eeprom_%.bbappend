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

    for FW in "${D}${base_libdir}/firmware/raspberrypi/bootloader-2712/default/"pieeprom-*.bin; do
        [ -f "${FW}" ] || continue

        bbnote "Signing EEPROM firmware: $(basename ${FW})"

        # Read current config from firmware binary and add SIGNED_BOOT=1
        ${PYTHON} "${S}/rpi-eeprom-config" "${FW}" > "${WORKDIR}/bootconf.txt"
        grep -q "^SIGNED_BOOT" "${WORKDIR}/bootconf.txt" || echo "SIGNED_BOOT=1" >> "${WORKDIR}/bootconf.txt"

        # Sign the config file: produces a .sig with SHA256 hash + RSA signature
        "${S}/rpi-eeprom-digest" -k "${KEY}" -i "${WORKDIR}/bootconf.txt" -o "${WORKDIR}/bootconf.sig"

        # Create signed binary in WORKDIR first, then install into ${D} under pseudo
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
