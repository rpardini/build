## Configuration
# @TODO: either - make sure the host has the needed tools (abootimg, mkimage, etc), apt install abootimg
# @TODO:     or - move the whole android-specific stuff inside the image and run during update-initramfs
# @TODO: use decent var names. early ones were rips from pmOS. (or: just curl/source the deviceinfo from there)

# We need to label the rootFS with an ext4 label so that we can find it, both at system and at userdata partitions.
# The user can choose where to flash it when it comes to fastboot flash.
# It is indeed hardcoded into the kernel cmdline, so the boot and rootfs images have to match.
export ROOT_FS_LABEL="Armbian_root"

## Hooks

# Early check for host-side tools needed for Android fastboot.
# This could benefit from a new hook_point "do_prepare_host" that actually allowed us to install them
user_config__200_check_android_fastboot_host_tools_installed() {
	# Check for mkbootimg and img2simg
	if [[ ! -f /usr/bin/mkbootimg ]] || [[ ! -f /usr/bin/img2simg ]]; then
		display_alert "Missing Android tools needed for build" "Install with: apt install -y mkbootimg android-sdk-libsparse-utils" "err"
		# @TODO: Armbian exit_with_?
		exit 3 # Hopefully abort the build.
	else
		display_alert "Android fastboot tooling" "ok" "info"
	fi
}

user_config__900_disable_all_image_fingerprints_and_compression() {
	export COMPRESS_OUTPUTIMAGE=fastboot # thy shall do nothing.
}

# the real images have been produced elsewhere (.fastboot.boot and .fastboot.rootfs .imgs)
post_build_image__800_discard_full_image() {
	[[ -f "${FINALDEST}/${version}.img" ]] && rm -f "${FINALDEST}/${version}.img"
	[[ -f "${FINALDEST}/${version}.img.txt" ]] && rm -f "${FINALDEST}/${version}.img.txt"
}

# last chance to modify mkopts and such, add labels to partitions
prepare_partitions_custom__add_rootfs_label_to_mkfs() {
	display_alert "prepare_partitions_custom oneplus adding to mfks ext4" "Label: ${ROOT_FS_LABEL}" "info"
	mkopts[ext4]="-L ${ROOT_FS_LABEL} ${mkopts[ext4]}"
}

# 990_ should be late enough in the game...
config_pre_umount_final_image__990_fastboot_create_boot_img() {
	display_alert "Creating Android fastboot boot.img" "Hook Order: ${HOOK_ORDER} of ${HOOK_POINT_TOTAL_FUNCS}" "info"

	# fastboot boot wants the gzipped kernel and concatenated dtb at the end. don't ask questions.
	gzip -9 --keep --no-name "$MOUNT"/boot/vmlinuz-*
	cat "$MOUNT"/boot/vmlinuz-*.gz "$MOUNT"/boot/dtb/"${BOOT_FDT_FILE}" >"$MOUNT"/boot/vmlinuz.gz.dtb

	# Prepare the android boot.img using mkbootimg -- this probably should move into initramfs generation,
	# create Armbian based boot.img for android fastboot.
	create_fastboot_boot_img "boot" "$MOUNT"/boot/initrd.img-* "root=LABEL=${ROOT_FS_LABEL} console=ttyGS0,115200 console=tty1 ${deviceinfo_kernel_cmdline}"

	# clean up. no need to keep intermediaries.
	rm "$MOUNT"/boot/vmlinuz-*.gz "$MOUNT"/boot/vmlinuz.gz.dtb
}

# 990_ should be quite late.
config_post_umount_final_image__990_extract_pure_ext4_image_from_partitioned_loop() {
	# @TODO: check that ${HOOK_ORDER} == ${HOOK_POINT_TOTAL_FUNCS} and warn if not.

	display_alert "Creating Android fastboot rootfs.img" "Hook Order: ${HOOK_ORDER} of ${HOOK_POINT_TOTAL_FUNCS}" "info"
	local wanted_partition="${LOOP}p1"
	local dest_img_file_tmp="${DEST}/images/${version}.fastboot.rootfs.img.nonsparse"
	local dest_img_file_final="${DEST}/images/${version}.fastboot.rootfs.img"
	pv -N "[ .... ] dd" "${wanted_partition}" >"${dest_img_file_tmp}"

	non_sparse_size="$(du -h -s "${dest_img_file_tmp}" | tr "\t" " " | cut -d " " -f 1)" # Really?
	display_alert "Converting to Android rootfs image sparse" "img2simg ${non_sparse_size}" "info"
	img2simg "${dest_img_file_tmp}" "${dest_img_file_final}"
	rm -f "${dest_img_file_tmp}"

	# @TODO of TODO: we already know the size (FIXED_SIZE_IMAGE?) yodumb. decide this beforehand!
	# @TODO: check non-sparse size against limit, on my OnePlus 5 'system' is 3gb while 'userdata' is 50gb+.
	#        use a ".system." filename if below the limit;
	#        use a ".userdata." filename if above the limit;

	# @TODO: also create an empty.img for easy system/userdata switching after the first flash.
}

# @TODO: a very late hook that checks a variable (FASTBOOT_DEVICE=c212167d) for a phone serial number and the presence of 'fastboot'
#        if present, do a default flashing dance (...fastboot -s c212167d flash system...)
#        it would be the equivalent of CARD_DEVICE for Fastboot (build and write all at once)

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
