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

tpm2_startauthsession -S "$WORKDIR/pol.ctx" --policy-session
tpm2_policypcr -S "$WORKDIR/pol.ctx" -l sha256:0,4,7

tpm2_unseal -c "$WORKDIR/sealed.ctx" -p "session:$WORKDIR/pol.ctx" \
    | cryptsetup luksOpen /dev/mmcblk0p3 securedata --key-file=-

tpm2_flushcontext "$WORKDIR/pol.ctx"

mkdir -p /run/securedata
mount -o nosuid,nodev,noexec /dev/mapper/securedata /run/securedata
