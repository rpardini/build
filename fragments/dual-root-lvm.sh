# Config
export DUAL_ROOT_FIXED_IMAGE_SIZE_GB=16 # 16gb is default. change in user config
export RESCUE_E2IMG=""                  # What e2img will be deployed to the fake/rescue root?

# Hooks
user_config__050_find_rescue_e2img_for_dual_root() {
	local rescueVersionPrefix="${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}"
	# shellcheck disable=SC2012
	export RESCUE_E2IMG=$(ls -1t "${DEST}/images/${rescueVersionPrefix}"*rescue*.e2img | head -1)
	if [[ ! -f "${RESCUE_E2IMG}" ]]; then
		display_alert "Rescue e2img" "Not found!" "err"
		exit 2
	else
		display_alert "Rescue e2img" "${RESCUE_E2IMG}" "info"
	fi

	export ROOTFS_IN_ROOTFS_EXPORT_ONLY=yes # We'll move it ourselves, thanks
}

prepare_image_size__900_add_second_root_fixed_size() {
	display_alert "DUAL ROOT uefi" "Total size ${DUAL_ROOT_FIXED_IMAGE_SIZE_GB}Gb (was: ${FIXED_IMAGE_SIZE}Mb)" ""
	export FIXED_IMAGE_SIZE=$((DUAL_ROOT_FIXED_IMAGE_SIZE_GB * 1024))
	export FAST_CREATE_IMAGE=yes      # This is very slow to zero out, use truncate
	export USE_HOOK_FOR_PARTITION=yes # Makes create_partition_table() hook be called instead of parted's.
}

create_partition_table__create_uefi_dual_root_partition() {
	# In this setup everything is fixed percentual sizes.
	# UEFI is fixed and steals from real root.
	# Real root is around 66% (2/3) of size
	# Rescue root is around 33% (1/3) of size
	# So calculate FIXED_IMAGE_SIZE accordingly.

	parted -s "${SDCARD}.raw" -- mkpart efi fat32 "0%" "256Mb"    # efi stuff
	parted -s "${SDCARD}.raw" -- mkpart root ext4 "256Mb" "67%"   # real root
	parted -s "${SDCARD}.raw" -- mkpart rescue ext4 "67%" "99%"   # rescue root, a little bigger
	parted -s "${SDCARD}.raw" -- mkpart thinlvm ext4 "99%" "100%" # lvm marker for extra data
	parted -s "${SDCARD}.raw" -- print || true
	display_alert "DUAL ROOT uefi" "Partitions created." ""
}

# At the end of build, with everything already unmounted, we'll populate ${LOOP}p3 via RESCUE_E2IMG
config_post_umount_final_image__850_deploy_rescue() {
	display_alert "DUAL ROOT uefi" "Will deploy ${RESCUE_E2IMG} to ${LOOP}p3" ""
	e2image -rap "${RESCUE_E2IMG}" "${LOOP}p3"
	fsck -y -f "${LOOP}p3"
	sync
	resize2fs "${LOOP}p3"
	sync
	fsck -y -f "${LOOP}p3"
	sync

	# mount it, include the new rootfs inside it, umount
	display_alert "DUAL ROOT uefi" "@TODO mount ${LOOP}p3" ""
	ls -la "${SRC}"/.tmp/rootfs.ext4.e2img

	mkdir -p "${SRC}"/.tmp/rescue
	mount "${LOOP}p3" "${SRC}"/.tmp/rescue
	cp -v "${SRC}"/.tmp/rootfs.ext4.e2img "${SRC}"/.tmp/rescue/root/rootfs.ext4.e2img
	sync

	# Now, fix the EFI reference in etc/fstab, otherwise rescue won't boot correctly AT ALL.
	# For the rescue, the efi is mounted read-only, since it will delegate to the
	# non-rescue /boot/grub/grub.cfg, and running update-grub from rescue should do nothing.
	mv "${SRC}"/.tmp/rescue/etc/fstab "${SRC}"/.tmp/rescue/etc/fstab.orig
	# shellcheck disable=SC2002
	cat "${SRC}"/.tmp/rescue/etc/fstab.orig | grep -v "${UEFI_MOUNT_POINT}" >"${SRC}"/.tmp/rescue/etc/fstab
	echo "UUID=$(blkid -s UUID -o value "${LOOP}p1") ${UEFI_MOUNT_POINT} vfat ro,defaults 0 2" >>"${SRC}"/.tmp/rescue/etc/fstab
	sync

	umount "${SRC}"/.tmp/rescue
	sync

	rmdir "${SRC}"/.tmp/rescue

	display_alert "DUAL ROOT uefi" "setup finished" ""

	# set this so e2img is not exported again by rootfs fragment
	export ROOTFS_IN_ROOTFS_EXPORT_ONLY=no
	rm -f "${SRC}"/.tmp/rootfs.ext4.e2img # clean up after ourselves, better off in rootfs fragment
}
