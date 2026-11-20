#!/bin/sh
# Extend PCR 8 with the firmware's view of this boot, before anything uses the TPM.
#
# U-Boot on RPi5 cannot reach the TPM (it sits behind RP1, which U-Boot has no
# driver for), so no pre-OS stage measures the boot chain. Instead we record the
# values the EEPROM firmware itself computed while RSA-verifying boot.img and
# exposed in /chosen/bootloader. Linux only transcribes them; the trust comes from
# the OTP-anchored secure boot chain that verified this kernel.
#
# PCR 8 = extend(extend(extend(0, boot.img), signed), version)
# Every value is a SHA-256 digest, so the final PCR is computable off-device.
set -e

export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
BL=/proc/device-tree/chosen/bootloader
PCR=8

measure() {
    tpm2_pcrextend "${PCR}:sha256=$2"
    echo "PCR ${PCR} += $1 $2"
}

# Firmware-computed SHA-256 of the boot.img it verified. The DT property is
# zero-padded beyond the 32-byte digest: read exactly 32 bytes.
BOOTIMG=$(head -c 32 "$BL/boot_img_sha256" | od -An -tx1 -v | tr -d ' \n')
if [ ${#BOOTIMG} -ne 64 ] || [ "$BOOTIMG" = "$(printf '0%.0s' $(seq 64))" ]; then
    echo "boot_img_sha256 missing or zero: boot.img was not verified" >&2
    exit 1
fi
measure boot.img "$BOOTIMG"

# Secure-boot status flags and EEPROM firmware build, as digests of the raw
# property bytes. tryboot/partition/count/rsts are deliberately NOT measured:
# they change legitimately between boots and between A/B slots.
measure signed  "$(sha256sum < "$BL/signed"  | cut -d' ' -f1)"
measure version "$(sha256sum < "$BL/version" | cut -d' ' -f1)"
