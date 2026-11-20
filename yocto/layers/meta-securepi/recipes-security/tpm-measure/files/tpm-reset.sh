#!/bin/sh
# Hardware-reset the discrete TPM so every boot starts from zeroed PCRs.
#
# The TPM's RST# line is wired to header GPIO 24 on the LetsTrust module
# (Infineon SLB9670/SLB9672). A warm `reboot` resets the SoC but neither cuts the
# header 3.3 V nor pulses RST#, so without this the TPM keeps the previous boot's
# PCRs and tpm-measure-boot extends on top of them. PCR 8 then never matches the
# sealed policy and the LUKS key stays locked.
#
# Sequence: unbind driver, RST# low, RST# high, rebind. The driver sends
# TPM2_Startup(CLEAR) on rebind. "TPM error (256)" in dmesg is TPM_RC_INITIALIZE,
# the expected result for a freshly reset TPM.
set -e

GPIO=24
DRV=/sys/bus/spi/drivers/tpm_tis_spi

DEV=$(basename "$(ls -d "$DRV"/spi* 2>/dev/null | head -1)")
if [ -z "$DEV" ] || [ "$DEV" = "." ]; then
    echo "tpm_tis_spi has no bound device: TPM not detected" >&2
    exit 1
fi

echo "$DEV" > "$DRV/unbind"
pinctrl set "$GPIO" op dl
sleep 0.1
pinctrl set "$GPIO" op dh
sleep 0.1
echo "$DEV" > "$DRV/bind"

# Wait for udev to recreate the device nodes, then make sure they carry
# tpm_device_t: services are only allowed to open that label.
udevadm settle --timeout=5
for i in $(seq 50); do
    [ -c /dev/tpmrm0 ] && [ -c /dev/tpm0 ] && break
    sleep 0.1
done
[ -c /dev/tpmrm0 ] || { echo "/dev/tpmrm0 did not reappear after reset" >&2; exit 1; }
restorecon /dev/tpm0 /dev/tpmrm0

echo "TPM reset via GPIO ${GPIO} (${DEV})"
