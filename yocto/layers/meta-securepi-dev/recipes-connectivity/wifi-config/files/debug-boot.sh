#!/bin/sh
# Writes boot debug info to the FAT32 boot partition after 30 seconds.
# Read it by mounting the card's boot partition on another machine after the device has booted.
sleep 30
mount -o remount,rw /boot 2>/dev/null || exit 0
{
    echo "=== SecurePi boot debug: $(date) ==="
    echo "--- Network interfaces ---"
    ip addr 2>&1
    echo "--- wpa_supplicant@wlan0 status ---"
    systemctl status wpa_supplicant@wlan0 --no-pager 2>&1
    echo "--- systemd-networkd status ---"
    systemctl status systemd-networkd --no-pager 2>&1
    echo "--- sshd.socket status ---"
    systemctl status sshd.socket --no-pager 2>&1
    echo "--- wpa_supplicant journal ---"
    journalctl -u wpa_supplicant@wlan0 --no-pager 2>&1
    echo "--- systemd-networkd journal ---"
    journalctl -u systemd-networkd --no-pager 2>&1
    echo "--- Loaded kernel modules ---"
    lsmod 2>&1
} > /boot/debug.log 2>&1
mount -o remount,ro /boot 2>/dev/null
