# Dev-layer additions: active only when meta-securepi-dev is in kas.yml.
# Adds network drivers, SSH server, and Wi-Fi credentials for hardware access.
IMAGE_INSTALL:append = " \
    wifi-config \
    openssh-sshd \
    wpa-supplicant \
    linux-firmware-rpidistro-bcm43455 \
    kernel-modules \
    sudo \
"
