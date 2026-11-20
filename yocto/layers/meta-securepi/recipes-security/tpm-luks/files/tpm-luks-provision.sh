#!/bin/sh
# One-time (re-)provisioning of the TPM-sealed LUKS data partition.
# DESTROYS everything on /dev/mmcblk0p3.
#
# Seals a fresh random LUKS key to the CURRENT value of PCR 8, so run it on a
# clean boot of the image that should be allowed to unlock, never after a
# manual tpm2_pcrextend, or the key is sealed to a value no boot reproduces.
#
# Robustness notes:
#   - close any stale mapping first, so mke2fs cannot write through it
#   - no pipes around critical steps: each command's exit status is checked
#     (exception: the key reaches cryptsetup on a pipe, see below. The pipe's
#     status is cryptsetup's, so set -e still catches a cryptsetup failure)
set -eu

export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
# mdev doesn't post the dm uevent semaphore: cryptsetup hangs without this
export DM_DISABLE_UDEV=1

DEV=/dev/mmcblk0p3
NV_PUB=0x01500010
NV_PRIV=0x01500011
PCRS=sha256:8

if ! systemctl is-active --quiet tpm-measure-boot.service; then
    echo "tpm-measure-boot.service has not run this boot: PCR 8 is not meaningful." >&2
    exit 1
fi

echo "This ERASES ${DEV} and replaces the TPM-sealed key. Type YES to continue:"
read -r ANSWER
[ "$ANSWER" = "YES" ] || { echo "Aborted."; exit 1; }

WORKDIR=$(mktemp -d /tmp/tpm-prov.XXXXXX)
cleanup() {
    rm -rf "$WORKDIR"
    tpm2_flushcontext --transient-object 2>/dev/null || true
}
trap cleanup EXIT

umount /run/securedata 2>/dev/null || true
cryptsetup close securedata 2>/dev/null || true

# 64 random bytes; lives only in tmpfs (/tmp) and, sealed, in the TPM.
# 64 B fits the TPM's 128 B limit for sealed data objects.
head -c 64 /dev/urandom > "$WORKDIR/key"

# Key goes to cryptsetup on stdin, like tpm-luks-unlock does. cryptsetup runs in
# the SELinux domain lvm_t, which may not open root's files in /tmp (user_tmp_t).
# That fails with "Failed to open key file." and no AVC (dontaudit rule).
echo "== LUKS2 format ${DEV}"
cat "$WORKDIR/key" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$DEV"
cat "$WORKDIR/key" | cryptsetup open --key-file=- "$DEV" securedata
mke2fs -q -t ext4 -L securedata /dev/mapper/securedata
cryptsetup close securedata

echo "== Seal key to ${PCRS}"
tpm2_pcrread "$PCRS"
# Same primary template as tpm-luks-unlock.sh: the owner hierarchy derives the
# identical key from it every boot, so the sealed blob can be reloaded.
tpm2_createprimary -C o -g sha256 -G ecc -c "$WORKDIR/primary.ctx"

tpm2_startauthsession -S "$WORKDIR/trial.ctx"
tpm2_policypcr -S "$WORKDIR/trial.ctx" -l "$PCRS" -L "$WORKDIR/pcr.policy"
tpm2_flushcontext "$WORKDIR/trial.ctx"

# Explicit attributes: no userwithauth, so the policy is the ONLY way to unseal
# (with userwithauth set, an empty password would bypass the PCR check).
tpm2_create -C "$WORKDIR/primary.ctx" \
    -L "$WORKDIR/pcr.policy" \
    -a "fixedtpm|fixedparent" \
    -i "$WORKDIR/key" \
    -u "$WORKDIR/sealed.pub" -r "$WORKDIR/sealed.priv"

echo "== Store sealed blob in TPM NVRAM"
for NV in "$NV_PUB" "$NV_PRIV"; do
    tpm2_nvundefine -C o "$NV" 2>/dev/null || true
done
tpm2_nvdefine -C o -s "$(stat -c %s "$WORKDIR/sealed.pub")"  -a "ownerread|ownerwrite" "$NV_PUB"
tpm2_nvwrite  -C o -i "$WORKDIR/sealed.pub"  "$NV_PUB"
tpm2_nvdefine -C o -s "$(stat -c %s "$WORKDIR/sealed.priv")" -a "ownerread|ownerwrite" "$NV_PRIV"
tpm2_nvwrite  -C o -i "$WORKDIR/sealed.priv" "$NV_PRIV"

echo "== Verify: unseal through the PCR policy and compare"
tpm2_load -C "$WORKDIR/primary.ctx" -u "$WORKDIR/sealed.pub" -r "$WORKDIR/sealed.priv" -c "$WORKDIR/sealed.ctx"
tpm2_startauthsession -S "$WORKDIR/pol.ctx" --policy-session
tpm2_policypcr -S "$WORKDIR/pol.ctx" -l "$PCRS"
tpm2_unseal -c "$WORKDIR/sealed.ctx" -p "session:$WORKDIR/pol.ctx" -o "$WORKDIR/check"
tpm2_flushcontext "$WORKDIR/pol.ctx"
cmp -s "$WORKDIR/key" "$WORKDIR/check" || { echo "Unsealed key does not match!" >&2; exit 1; }

echo "Provisioned. Start the unlock with: systemctl restart tpm-luks-unlock"
