source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

# Config
export RASPI_ROOT_FS_LABEL="armbian"
export RASPI_KERNEL_PACKAGES="rpi-eeprom raspi-config linux-firmware-raspi2 linux-tools-raspi linux-raspi linux-image-raspi"
export RASPI_FLASH_PACKAGES="flash-kernel"
export RASPI_MACHINE_MODEL="Raspberry Pi 4 Model B"

# @TODO: refactor, split into use-ubuntu-kernel (also for x86) and use-flash-kernel

# Hooks
user_config__disable_kernel_compile() {
	unset KERNELSOURCE                                 # This should make Armbian skip most stuff. At least, I hacked it to.
	export UEFISIZE=256                                # in MiB
	export BOOTSIZE=0                                  # No separate /boot when using UEFI.
	export UEFI_MOUNT_POINT="/boot/firmware"           # mount uefi part at /boot/firmware
	export CLOUD_INIT_CONFIG_LOCATION="/boot/firmware" # use /boot/firmware for cloud-init as well

	# Zero out the log for this fragment.
	echo -n "" >>"${DEST}"/debug/raspi.log
}

# These used to be in PACKAGE_LIST_BOARD, but there is a bit of a conundrum with flash-kernel.
# A bit of a conundrum with kernel vs flash-kernel.
# We need to install flash-kernel before the kernel, so that we can then disable/hack it
# Before actually installing the kernel (which will fail if we don't hack)
post_install_kernel_debs__install_raspi_ubuntu_kernel_and_flash() {
	display_alert "Installing raspi kernel" "${RASPI_KERNEL_PACKAGES}"
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get ${apt_extra_dist} -yqq --no-install-recommends install ${RASPI_KERNEL_PACKAGES}" >>"${DEST}"/debug/raspi.log

	display_alert "Installing raspi flash" "${RASPI_FLASH_PACKAGES}"
	# Create a fake /sys/firmware/efi directory so that flash-kernel does not try to do anything when installed
	# @TODO: this might or not work after flash-kernel 3.104 or later
	umount "${SDCARD}"/sys
	mkdir -p "${SDCARD}"/sys/firmware/efi
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get ${apt_extra_dist} -yqq --no-install-recommends install ${RASPI_FLASH_PACKAGES}" >>"${DEST}"/debug/raspi.log

	# Remove fake /sys/firmware (/efi) directory
	rm -rf "${SDCARD}"/sys/firmware

	#display_alert "Disabling raspi" "flash-kernel"
	#chroot "${SDCARD}" /bin/bash -c "chmod -v -x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/debug/raspi.log
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
	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" >>"${DEST}"/debug/raspi.log 2>&1

	local flash_kernel_cmd="flash-kernel --machine '${RASPI_MACHINE_MODEL}'"
	display_alert "Raspi flash-kernel" "${RASPI_MACHINE_MODEL}" "info"
	chroot $chroot_target /bin/bash -c "${flash_kernel_cmd}" >>"${DEST}"/debug/raspi.log 2>&1

	display_alert "Re-enabling" "initramfs-tools/flash-kernel hook for kernel"
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/debug/raspi.log 2>&1
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/debug/raspi.log 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY
}

# Internal Functions
write_raspi_config() {
	cat <<-EOD >"${MOUNT}"/boot/firmware/config.txt
		[pi4]
		max_framebuffers=2

		[all]
		kernel=vmlinuz
		cmdline=cmdline.txt
		initramfs initrd.img followkernel

		# dt params. dunno what are those
		dtparam=audio=on
		dtparam=i2c_arm=on
		dtparam=spi=on

		# default maybe
		disable_overscan=1

		# dunno
		hdmi_drive=2

		arm_64bit=1

		# bootloader logs to serial
		# enable_uart=1
		# there is also 'BOOT_UART=1' in 'rpi-eeprom-config' but that is for an earlier stage.
		# look at with it rpi-eeprom-config
		# change with 'EDITOR=nano rpi-eeprom-config --edit'

		# overclock. requires decent thermals.
		over_voltage=6
		arm_freq=2000

		# disable stuff.
		dtoverlay=disable-wifi
		dtoverlay=disable-bt

		# gpu stuff. on 64-bit, its just like panfrost, should work but doesnt, gets better with time
		# I dont use it at all, but leave enabled for future
		gpu_mem=256
		dtoverlay=vc4-fkms-v3d

		# force dwc2, sometimes better for otg stuff and
		# dtoverlay=dwc2
	EOD
}
write_raspi_cmdline() {
	# @TODO: consider maybe DEFAULT_CONSOLE, for UART-first console which is great for debugging stuff
	#        console=serial0,115200
	cat <<-EOD >"${MOUNT}"/boot/firmware/cmdline.txt
		root=LABEL=${RASPI_ROOT_FS_LABEL} rootfstype=ext4 elevator=deadline rootwait fixrtc cgroup_enable=memory cgroup_memory=1 console=tty1
	EOD
}
