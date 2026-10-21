# Dev-layer additions: active only when meta-securepi-dev is in kas.yml.
# Enables Wi-Fi + SSH access for development. Primary access is serial console.
IMAGE_INSTALL:append = " \
    wifi-config \
    openssh \
    openssh-sftp-server \
    openssh-sshd \
    wpa-supplicant \
    linux-firmware-rpidistro-bcm43455 \
    kernel-modules \
"
