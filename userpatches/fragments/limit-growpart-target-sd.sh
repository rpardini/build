# Ok so here we write an extra partition to the SD card, if that was written.
# This is convenience only, to limit the size to which growpart/growroot will grow the rootfs.
# It is only done directly on the CARD_DEV device after flashing the img to it.

# Config
export GROW_LIMIT_GB=16 # adds a partition of the device that wont allow growpart to grow beyond it

# Hooks
post_write_sdcard__create_growmarker_partition() {
	display_alert "Creating growmarker partition" "${CARD_DEVICE}" "info"
	sync # wait for the flashing to finish
	parted -s "${CARD_DEVICE}" -- mkpart primary ext4 $((GROW_LIMIT_GB * 1024))MiB $(((GROW_LIMIT_GB * 1024) + 1))MiB || echo "Failed creating growmaker partition on ${CARD_DEVICE}"
}

# parted -s "/dev/sda" -- mkpart primary ext4 $((24 * 1024))MiB $(((24 * 1024) + 1))MiB
