source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

# Config
export DKB_ROOT_FS_LABEL="armbian"

# Hooks
user_config__prepare_dkb() {
	export IMAGE_PARTITION_TABLE="gpt" # GPT is not required for Direct Kernel Boot, but why not?
	export BOOTSIZE=0                  # No separate /boot when using DKB
	export COMPRESS_OUTPUTIMAGE=img    # Just the image, please.

	# get rid of packages not really applicable to DKB.
	remove_packages_everywhere cpufrequtils fake-hwclock haveged rfkill sunxi-tools device-tree-compiler u-boot-tools kbd

	# do not write SDCARD for dkb, it makes no sense.
	export CARD_DEVICE=""
}

# Add a label to the partition, so DKB user does not need to type/know "/dev/vda1"
prepare_partitions_custom__add_rootfs_label_to_mkfs() {
	display_alert "DKB rootfs label ${DKB_ROOT_FS_LABEL}" "boot with root=LABEL=${DKB_ROOT_FS_LABEL}" "info"
	mkopts[ext4]="-L ${DKB_ROOT_FS_LABEL} ${mkopts[ext4]}"
}

pre_umount_final_image__900_capture_kernel_and_initramfs() {
	display_alert "Extracting Kernel and Initrd for" "Direct Kernel Boot" "info"

	# disarm bomb that was planted by the bsp. @TODO: move to bsp tweaks hook
	rm -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot

	local dest_kernel="${DEST}/images/${version}.kernel"
	local dest_initrd="${DEST}/images/${version}.initrd"

	# capture the $MOUNT/boot/vmlinuz and initrd and sent it out ${DEST}
	cp "$MOUNT"/boot/vmlinuz-* "${dest_kernel}"
	cp "$MOUNT"/boot/initrd.img-* "${dest_initrd}"

	# export the names for example cmdline to run later.
	export DKB_KERNEL="${dest_kernel}"
	export DKB_INITRD="${dest_initrd}"
}
