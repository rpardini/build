config_prepare_image_size__rootfs_predict_image_size() {
	# For this to work we need a very big image size. We''ll fill it with itself, so get the size and double it at least.
	# Note: the file is sparse, meaning that is shows larger than it actually is (filled with zeroes).
	# For now well use triple the size.
	export FIXED_IMAGE_SIZE=$(("${rootfs_size}" * 3))
	display_alert "Determined FIXED_IMAGE_SIZE to be" "${FIXED_IMAGE_SIZE}" "info"
}

config_pre_umount_final_image__prepare_rootfs_inside_rootfs() {
	# For sure there is an Armbian env (LOOP_X?) but I didnt figure it out a the time.
	export ROOT_LOOP_DEV_PART=$(mount | grep "${MOUNT}" | grep ext4 | cut -d " " -f 1)
}

# No real need to compress. The file created is sparse, and ext4 works ok with those.
# Also, xz has a ball finding double blocks in the final image.

config_post_umount_final_image__rootfs_e2img_inside_rootfs() {
	# to make sure its unmounted - copied from Armbian codebase, but does not really work.
	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts; do
		display_alert "Waiting for unmount...." "${MOUNT}" "info"
		sleep 1 && sync
	done

	#make sure it is completely clean...
	display_alert "fsck" "${ROOT_LOOP_DEV_PART}" "info"
	fsck.ext4 -y "${ROOT_LOOP_DEV_PART}" >/dev/null 2>&1

	display_alert "e2image dumping" "${ROOT_LOOP_DEV_PART}" "info"
	e2image -rap "${ROOT_LOOP_DEV_PART}" "${MOUNT}/../rootfs.ext4.e2img" >/dev/null 2>&1
	sync

	apparent_size=$(du -h --apparent-size "${MOUNT}/../rootfs.ext4.e2img" | tr -s "\t" "|" | cut -d "|" -f 1)
	actual_size=$(du -h "${MOUNT}/../rootfs.ext4.e2img" | tr -s "\t" "|" | cut -d "|" -f 1)

	display_alert "e2image sparse dump done" "sizes: apparent: ${apparent_size} actual: ${actual_size} imgsize: ${FIXED_IMAGE_SIZE}Mb" "info"

	echo -n "[ .... ] Re-mounting..."
	mount "${ROOT_LOOP_DEV_PART}" "${MOUNT}" && sync

	echo -n "Copying..."
	# pipes and sparse files don't mix. be simple about the copy, although it is huge.
	cp "${MOUNT}/../rootfs.ext4.e2img" "${MOUNT}/root/rootfs.ext4.e2img" || {
		echo "" # break a line so error is clearly visible
		display_alert "e2image sparse copy failed" "sizes: apparent: ${apparent_size} actual: ${actual_size} imgsize: ${FIXED_IMAGE_SIZE}" "err"
	}
	sync

	echo -n "Unmount..."
	umount "${MOUNT}" && sync

	echo -n "Clean..."
	#mkdir -p "${DEST}"/images
	#mv "${MOUNT}"/../rootfs.ext4.e2img "${DEST}/images/${version}.rootfs.ext4.e2img"
	rm -f "${MOUNT}"/../rootfs.ext4.e2img

	echo -n "Sync again..."
	sync

	echo "done."
}
