## Configuration

# @TODO: either - make sure the host has the needed tools (abootimg, mkimage, etc), apt install abootimg
# @TODO:     or - move the whole android-specific stuff inside the image and run during update-initramfs
# @TODO: use decent var names. early ones were rips from pmOS. (or: just curl/source the deviceinfo from there)

# We need to label the rootFS with an ext4 label so that we can find it, both at system and at userdata partitions.
# The user can choose where to flash it when it comes to fastboot flash.
# It is indeed hardcoded into the kernel cmdline, so the boot and rootfs images have to match.
export ROOT_FS_LABEL="Armbian_root"

## Hooks
user_config__900_disable_all_image_fingerprints_and_compression() {
	export COMPRESS_OUTPUTIMAGE=none_at_all_hopefully
}

# the real images have been produced elsewhere (.fastboot.boot and .fastboot.rootfs .imgs)
post_build_image__discard_full_image() {
	[[ -f "${FINALDEST}/${version}.img" ]] && rm -f "${FINALDEST}/${version}.img"
	[[ -f "${FINALDEST}/${version}.img.txt" ]] && rm -f "${FINALDEST}/${version}.img.txt"
}

# last chance to modify mkopts and such, add labels to partitions
prepare_partitions_custom__add_rootfs_label_to_mkfs() {
	display_alert "prepare_partitions_custom oneplus adding to mfks ext4" "Label: ${ROOT_FS_LABEL}" "info"
	mkopts[ext4]="-L ${ROOT_FS_LABEL} ${mkopts[ext4]}"
}

config_pre_umount_final_image__androidfastboot_extract_kernel() {
	# fastboot boot wants the gzipped kernel and concatenated dtb at the end. don't ask questions.
	gzip -9 --keep --no-name "$MOUNT"/boot/vmlinuz-*
	cat "$MOUNT"/boot/vmlinuz-*.gz "$MOUNT"/boot/dtb/"${BOOT_FDT_FILE}" >"$MOUNT"/boot/vmlinuz.gz.dtb

	# Prepare the android boot.img using mkbootimg -- this probably should move into initramfs generation,
	# create Armbian based boot.img for android fastboot.
	create_fastboot_boot_img "boot" "$MOUNT"/boot/initrd.img-* "root=LABEL=${ROOT_FS_LABEL} console=ttyGS0,115200 console=tty1 ${deviceinfo_kernel_cmdline}"
}

config_post_umount_final_image__extract_pure_ext4_image_from_partitioned_loop() {
	local wanted_partition="${LOOP}p1"
	local dest_img_file="${DEST}/images/${version}.fastboot.rootfs.img"
	pv -N "[ .... ] dd" "${wanted_partition}" >"${dest_img_file}"
}

## internal functions

create_fastboot_boot_img() {
	local id="$1"      # boot
	local ramdisk="$2" # ramdisk
	local cmdline="$3" # deviceinfo_kernel_cmdline
	local dest_output="${DEST}/images/${version}.fastboot.${id}.img"
	local boot_output="${MOUNT}/boot/fastboot.${id}.img"

	mkbootimg \
		--kernel "$MOUNT"/boot/vmlinuz.gz.dtb \
		--ramdisk "${ramdisk}" \
		--base "${deviceinfo_flash_offset_base}" \
		--second_offset "${deviceinfo_flash_offset_second}" \
		--cmdline "${cmdline}" \
		--kernel_offset "${deviceinfo_flash_offset_kernel}" \
		--ramdisk_offset "${deviceinfo_flash_offset_ramdisk}" \
		--tags_offset "${deviceinfo_flash_offset_tags}" \
		--pagesize "${deviceinfo_flash_pagesize}" \
		-o "${boot_output}"

	# Copy to dest too, since user will need to flash it via fastboot.
	cp "${boot_output}" "${dest_output}"
	display_alert "Android boot.img for fastboot" "${id}: .fastboot.${id}.img suffix" "info"

}
