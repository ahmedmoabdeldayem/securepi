#!/usr/bin/env bash
# Flash the latest SecurePi image to SD card.
# Run on the build host with the SD card attached (card reader or USB passthrough).
#
# Usage:
#   ./flash-sd.sh: auto-detect card and latest image
#   ./flash-sd.sh /dev/sdb: specify device explicitly

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE_DIR="$REPO_ROOT/build/tmp/deploy/images/raspberrypi5"
IMAGE=$(ls -t "$IMAGE_DIR"/securepi-image-raspberrypi5.rootfs.wic.bz2 2>/dev/null | head -1)

# Auto-detect SD card: first removable disk that is not a typical system disk (vda/nvme0n1)
DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
    DEVICE=$(lsblk -o NAME,RM,TYPE --noheadings | awk '$2=="1" && $3=="disk" {print "/dev/"$1}' | grep -v vda | head -1)
fi

if [[ -z "$IMAGE" ]]; then
    echo "ERROR: No image found in $IMAGE_DIR"
    echo "Run 'bitbake securepi-image' first."
    exit 1
fi

if [[ -z "$DEVICE" ]]; then
    echo "ERROR: No removable disk found."
    echo "Attach the SD card, then run: lsblk"
    exit 1
fi

# Safety: refuse system disks
if echo "$DEVICE" | grep -qE '^/dev/(vda|nvme0n1)$'; then
    echo "ERROR: $DEVICE looks like a system disk. Aborting."
    echo "Check with: lsblk"
    exit 1
fi

SIZE=$(lsblk -o SIZE --noheadings "$DEVICE" | head -1 | xargs)
echo "Image : $IMAGE"
echo "Device: $DEVICE ($SIZE)"
echo ""
echo "ALL DATA ON $DEVICE WILL BE DESTROYED."
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

# Unmount any mounted partitions
for part in "${DEVICE}"?*; do
    if mountpoint=$(lsblk -no MOUNTPOINT "$part" 2>/dev/null) && [[ -n "$mountpoint" ]]; then
        echo "Unmounting $part ($mountpoint)"
        sudo umount "$part" 2>/dev/null || true
    fi
done

echo "Flashing..."
bzcat "$IMAGE" | sudo dd of="$DEVICE" bs=4M conv=fsync status=progress

echo ""
echo "Ejecting $DEVICE..."
sudo eject "$DEVICE"

echo ""
echo "Done. It is now safe to remove the card."
