source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

# Config
export DKB_ROOT_FS_LABEL="armbian"
export UBUNTU_KERNEL=no # if yes, does not build our own kernel, instead, uses one from Ubuntu.

# Hooks
user_config__prepare_dkb() {
	export IMAGE_PARTITION_TABLE="gpt" # GPT is not required for Direct Kernel Boot, but why not?
	export BOOTSIZE=0                  # No separate /boot when using DKB
	export COMPRESS_OUTPUTIMAGE=img    # Just the image, please.

	# get rid of packages not really applicable to DKB.
	remove_packages_everywhere cpufrequtils fake-hwclock haveged rfkill sunxi-tools device-tree-compiler u-boot-tools kbd

	# @TODO: Hmm. Errors on arm64 buildhost if armbian-config is NOT included above, why?

	# do not write SDCARD for dkb, it makes no sense.
	export CARD_DEVICE=""

	# disable most of cloud-config configuration (not install)
	export SKIP_CLOUD_INIT_CONFIG=yes

	if [[ "${UBUNTU_KERNEL}" == "yes" ]]; then
		export VER="generic"
		export PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD} linux-firmware linux-image-generic"
		unset KERNELSOURCE # This should make Armbian skip most stuff. At least, I hacked it to.
	fi
}


post_family_tweaks_bsp__do_not_use_uboot_initramfs() {
	display_alert "BSP removing" "99-uboot hook"
	rm "$destination"/etc/initramfs/post-update.d/99-uboot || true
}

pre_umount_final_image__disable_uboot_initramfs() {
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && display_alert "u-boot customization should not be in BSP" "/etc/initramfs/post-update.d/99-uboot" "err"
}

pre_update_initramfs__initrd_all_kernels() {
	[[ "${UBUNTU_KERNEL}" != "yes" ]] && return 0

	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && display_alert "u-boot customization should not exist" "/etc/initramfs/post-update.d/99-uboot" "err"

	local chroot_target=$MOUNT
	cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/" # this already handles /boot/firmware which is required for it to work.
	local update_initramfs_cmd="update-initramfs -c -k all"
	display_alert "Updating DKB initramfs..." "$update_initramfs_cmd" ""
	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" #>>"${DEST}"/debug/install.log 2>&1
	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/debug/install.log 2>&1
	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY
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
