source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

# Config
export RASPI_ROOT_FS_LABEL="armbian"

# Hooks
user_config__disable_kernel_compile() {
	unset KERNELSOURCE                                 # This should make Armbian skip most stuff. At least, I hacked it to.
	export UEFISIZE=256                                # in MiB
	export BOOTSIZE=0                                  # No separate /boot when using UEFI.
	export UEFI_MOUNT_POINT="/boot/firmware"           # mount uefi part at /boot/firmware
	export CLOUD_INIT_CONFIG_LOCATION="/boot/firmware" # use /boot/firmware for cloud-init as well
}

# Add a label to the root partition - this is common, should refactor into a separate segment
prepare_partitions_custom__add_rootfs_raspi_label_to_mkfs() {
	display_alert "raspi rootfs label ${RASPI_ROOT_FS_LABEL}" "boot with root=LABEL=${RASPI_ROOT_FS_LABEL}" "info"
	mkopts[ext4]="-L ${RASPI_ROOT_FS_LABEL} ${mkopts[ext4]}"
}

pre_umount_final_image__install_grub() {
	# disarm bomb that was planted by the bsp. @TODO: move to bsp tweaks hook
	rm -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot
}

pre_update_initramfs__setup_flash_kernel() {
	write_raspi_config
	write_raspi_cmdline

	local chroot_target=$MOUNT

	cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/" # this already handles /boot/firmware which is required for it to work.

	# hack, umount the chroot's /sys, otherwise flash-kernel tries to EFI flash due to the build host (!) being EFI
	umount "$chroot_target/sys"

	local update_initramfs_cmd="update-initramfs -c -k all"
	display_alert "Updating raspi initramfs..." "$update_initramfs_cmd" ""
	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" >>"${DEST}"/debug/install.log 2>&1

	local flash_kernel_cmd="flash-kernel --machine 'Raspberry Pi 4 Model B'"
	display_alert "Raspi flash-kernel" "${flash_kernel_cmd}" "info"
	chroot $chroot_target /bin/bash -c "${flash_kernel_cmd}" >>"${DEST}"/debug/install.log 2>&1

	display_alert "Re-enabling" "initramfs-tools/flash-kernel hook for kernel"
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/debug/install.log 2>&1
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/debug/install.log 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY
}

#pre_umount_final_image__show_stuff() {
#	echo "SHOW STUFF"
#	tree $MOUNT/boot
#}

# Internal Functions
write_raspi_config() {
	cat <<-EOD >"${MOUNT}"/boot/firmware/config.txt
		[pi4]
		max_framebuffers=2
		[all]
		kernel=vmlinuz
		cmdline=cmdline.txt
		initramfs initrd.img followkernel
		dtparam=audio=on
		dtparam=i2c_arm=on
		dtparam=spi=on
		enable_uart=1
		disable_overscan=1
		arm_64bit=1
		dtoverlay=dwc2
		enable_uart=1
		over_voltage=6
		arm_freq=2000
		dtoverlay=disable-wifi
		dtoverlay=disable-bt
		hdmi_drive=2
		gpu_mem=256
		dtoverlay=vc4-fkms-v3d
	EOD
}
write_raspi_cmdline() {
	# I dont use hdmi: console=tty1
	cat <<-EOD >"${MOUNT}"/boot/firmware/cmdline.txt
		dwc_otg.lpm_enable=0 root=LABEL=${RASPI_ROOT_FS_LABEL} rootfstype=ext4 elevator=deadline rootwait fixrtc cgroup_enable=memory cgroup_memory=1 console=serial0,115200
	EOD
}
