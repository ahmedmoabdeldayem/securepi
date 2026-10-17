#!/usr/bin/env bash
# Flashes a Yocto WIC image to an SD card.
# Run on the build host with the SD card attached.
#
# Usage: ./flash-sd.sh <image.wic.bz2> <device>
#   e.g: ./flash-sd.sh tmp/deploy/images/raspberrypi5/securepi-image-raspberrypi5.wic.bz2 /dev/sdb
#
# WARNING: Double-check the device path. This will DESTROY all data on it.

set -euo pipefail

IMAGE="${1:-}"
DEVICE="${2:-}"

if [[ -z "$IMAGE" || -z "$DEVICE" ]]; then
    echo "Usage: $0 <image.wic[.bz2]> <device>"
    echo "  e.g: $0 securepi-image-raspberrypi5.wic.bz2 /dev/sdb"
    exit 1
fi

if [[ ! -f "$IMAGE" ]]; then
    echo "ERROR: Image file not found: $IMAGE"
    exit 1
fi

# Safety check: refuse if device looks like a system disk
if echo "$DEVICE" | grep -qE '^/dev/(sda|nvme0n1|vda)$'; then
    echo "ERROR: Refusing to write to what looks like a system disk: $DEVICE"
    echo "Double-check your device with: lsblk"
    exit 1
fi

echo "About to write $IMAGE to $DEVICE"
echo "All data on $DEVICE will be DESTROYED."
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

# Unmount any mounted partitions
lsblk -no MOUNTPOINT "$DEVICE" | grep -v '^$' | while read -r mount; do
    echo "Unmounting $mount"
    sudo umount "$mount" 2>/dev/null || true
done

echo "Flashing..."
if [[ "$IMAGE" == *.bz2 ]]; then
    sudo sh -c "bzip2 -dc '${IMAGE}' | dd of='${DEVICE}' bs=4M conv=fsync status=progress"
elif [[ "$IMAGE" == *.zst ]]; then
    sudo sh -c "zstd -dc '${IMAGE}' | dd of='${DEVICE}' bs=4M conv=fsync status=progress"
else
    sudo dd if="$IMAGE" of="$DEVICE" bs=4M conv=fsync status=progress
fi

sudo sync
echo ""
echo "Done. Safely eject ${DEVICE} and insert into Raspberry Pi 5."
