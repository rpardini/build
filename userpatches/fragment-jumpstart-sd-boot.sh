#! /bin/bash

# These boards need to boot from an UUID... not LABEL=xx
export SD_ROOT_DEV="UUID=11111111-1111-1111-1111-111111111111";

# last chance to modify mkopts and such, add labels to partitions
prepare_partitions_custom() {
	display_alert "Custom config stage" "prepare_partitions_custom" "info"

	echo "existing fat opts: ${mkopts[fat]}"
	echo "existing ext4 opts: ${mkopts[ext4]}"
	mkopts[ext4]="-U ${SD_ROOT_DEV} ${mkopts[ext4]}"
	echo "new ext4 opts: ${mkopts[ext4]}"
	echo "new fat opts: ${mkopts[fat]}"
}




image_tweaks_pre_customize__jumpstart() {
	display_alert "Custom config stage" "image_tweaks_pre_customize__jumpstart" "info"

	##### # Expand the binaries.
	##### # Right now there is a 50mb blob of balbes150's last working build.
	##### # This should be replaced with a torrent download or something like that.
	##### # Also if you respect the layout you can use any other kernel/initrd/uboot combination that works for your board.
	JUMPSTART_BINARY_TARBALL="$USERPATCHES_PATH/overlay/jumpstart/${JUMPSTART_ID}.tar.xz"
	if [[ -f "${JUMPSTART_BINARY_TARBALL}" ]]; then
		display_alert "Expanding binary pack" "${JUMPSTART_BINARY_TARBALL}" "info"
		PRE_PWD="$(pwd)" cd "$USERPATCHES_PATH/overlay" || exit 1
		[[ ! -f untarred ]] && tar xJf "${JUMPSTART_ID}.tar.xz" && touch untarred
		cd "${PRE_PWD}" || exit 2
	fi

	# Copy over the expanded balbe stuff from the overlay. it shall not overwrite anything...
	cp -r "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/* "${SDCARD}"/boot/
	cp -r "${USERPATCHES_PATH}"/overlay/jumpstart/sd-root-root/* "${SDCARD}"/root/

	# These two will come from the binary pack.
	[[ -d "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot-kernel ]] && cp -r "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot-kernel/* "${SDCARD}"/boot/
	[[ -d "${USERPATCHES_PATH}"/overlay/jumpstart/sd-root-lib-modules ]] && cp -r "${USERPATCHES_PATH}"/overlay/jumpstart/sd-root-lib-modules/* "${SDCARD}"/lib/modules/ # @TODO: clean this in flash-emmc.sh

	# remove armbianEnv.txt -- would be very confusing if both extlinux and armbianEnv where on an SD card.
	# @TODO: also debootstrap.sh manipulates it directly if it exists, after customizing the image. Which is bad.
	mv -v "${SDCARD}"/boot/armbianEnv.txt "${SDCARD}"/boot/preJumpstart_armbianEnv.txt || true

	echo "... processing jumpstart templates ..."
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-emmc-built-kernel.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-emmc-built-kernel.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-jumpstart-balbe.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-jumpstart-balbe.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-jumpstart-built-kernel.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-jumpstart-built-kernel.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-root-root/flash_emmc.sh | process_jumpstart_template >"${SDCARD}"/root/flash_emmc.sh

	echo ".... will use ${CHOSEN_EXTLINUX_JUMPSTART} for jumpstart ..."
	cp -v "${SDCARD}/boot/extlinux/${CHOSEN_EXTLINUX_JUMPSTART}" "${SDCARD}"/boot/extlinux/extlinux.conf

	cp -rv "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/autoscripts "${SDCARD}"/boot/
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/aml_autoscript.txt "${SDCARD}"/boot/aml_autoscript
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/emmc_autoscript.txt "${SDCARD}"/boot/emmc_autoscript
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/s905_autoscript.txt "${SDCARD}"/boot/s905_autoscript

	echo ".... creating aml_autoscript.zip ...."
	echo "fake zip for for android to boot from this sd card" >"${SDCARD}"/boot/aml_autoscript.zip

	# for sure boot.cmd and boot.scr are not used, at least for s912
	# rm -f "${SDCARD}"/boot/boot.cmd "${SDCARD}"/boot/boot.scr

	#@ TODO: what about boot.ini ???

	# balbe150 provides 3 variations of u-boot, configure in <board>.conf
	cp "${SDCARD}/boot/${JUMPSTART_UBOOT}" "${SDCARD}"/boot/u-boot.ext
}

# process template from stdin to stdout using the vars
process_jumpstart_template() {
	cat - |
		awk "{gsub(\"@@EMMC_KNOWN_GOOD_BOOTLOADER_EMMC@@\",\"${EMMC_KNOWN_GOOD_BOOTLOADER_EMMC}\"); print}" |
		awk "{gsub(\"@@EXTRACMDLINE_JUMPSTART@@\",\"${EXTRACMDLINE_JUMPSTART}\"); print}" |
		awk "{gsub(\"@@EXTRACMDLINE_EMMC@@\",\"${EXTRACMDLINE_EMMC}\"); print}" |
		awk "{gsub(\"@@CHOSEN_EXTLINUX_EMMC@@\",\"${CHOSEN_EXTLINUX_EMMC}\"); print}" |
		awk "{gsub(\"@@CHOSEN_EXTLINUX_JUMPSTART@@\",\"${CHOSEN_EXTLINUX_JUMPSTART}\"); print}" |
		awk "{gsub(\"@@SERIALCON@@\",\"${SERIALCON}\"); print}" |
		awk "{gsub(\"@@BOARD@@\",\"${BOARD}\"); print}" |
		awk "{gsub(\"@@BOARD_NAME@@\",\"${BOARD_NAME}\"); print}" |
		awk "{gsub(\"@@JUMPSTART_UBOOT@@\",\"${JUMPSTART_UBOOT}\"); print}" |
		awk "{gsub(\"@@JUMPSTART_DTB@@\",\"${JUMPSTART_DTB}\"); print}" |
		awk "{gsub(\"@@BOOT_FDT_FILE@@\",\"${BOOT_FDT_FILE}\"); print}" |
		awk "{gsub(\"@@KERNEL_IMAGE_TYPE@@\",\"${KERNEL_IMAGE_TYPE}\"); print}" |
		awk "{gsub(\"@@JUMPSTART_ID@@\",\"${JUMPSTART_ID}\"); print}" |
		awk "{gsub(\"@@SD_ROOT_DEV@@\",\"${SD_ROOT_DEV}\"); print}"
}
