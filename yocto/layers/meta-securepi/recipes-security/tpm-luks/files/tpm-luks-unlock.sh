#!/bin/sh
set -e

export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
# mdev on this image doesn't post the dm uevent semaphore, and without this
# cryptsetup hangs indefinitely waiting for a udev event that never arrives
export DM_DISABLE_UDEV=1

WORKDIR=$(mktemp -d /tmp/tpm-luks.XXXXXX)
cleanup() {
    rm -rf "$WORKDIR"
    tpm2_flushcontext --transient-object 2>/dev/null || true
}
trap cleanup EXIT

tpm2_createprimary -C o -g sha256 -G ecc -c "$WORKDIR/primary.ctx"

tpm2_nvread -C o 0x01500010 > "$WORKDIR/sealed.pub"
tpm2_nvread -C o 0x01500011 > "$WORKDIR/sealed.priv"

tpm2_load -C "$WORKDIR/primary.ctx" \
    -u "$WORKDIR/sealed.pub" \
    -r "$WORKDIR/sealed.priv" \
    -c "$WORKDIR/sealed.ctx"

# -c primary.ctx makes this a SALTED session: the Pi sends the TPM a random salt
# encrypted to the TPM's public key, so both derive a shared session key an SPI
# bus sniffer can't compute. --enable-encrypt then makes the TPM AES-encrypt the
# unseal RESPONSE (the 64-byte LUKS key) on the wire. Without this the key crosses
# the SPI bus in clear text and a logic analyzer recovers it from one boot.
tpm2_startauthsession -S "$WORKDIR/pol.ctx" --policy-session -c "$WORKDIR/primary.ctx"
tpm2_sessionconfig "$WORKDIR/pol.ctx" --enable-encrypt
# PCR 8 is extended by tpm-measure-boot.service with the firmware-verified boot.img
# digest, secure-boot flags and EEPROM version. PCRs 0-7 stay zero on RPi5.
tpm2_policypcr -S "$WORKDIR/pol.ctx" -l sha256:8

tpm2_unseal -c "$WORKDIR/sealed.ctx" -p "session:$WORKDIR/pol.ctx" \
    | cryptsetup luksOpen /dev/mmcblk0p3 securedata --key-file=-

tpm2_flushcontext "$WORKDIR/pol.ctx"

mkdir -p /run/securedata
mount -o nosuid,nodev,noexec /dev/mapper/securedata /run/securedata
