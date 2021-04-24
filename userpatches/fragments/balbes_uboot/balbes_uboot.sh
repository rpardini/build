# This is very old stuff pre-2020. 
# In the end, I used up a zeroed out eMMC, sd card from this build with balbe's uboot + uboot.ext + extlinux and it worked.
# I saw some recent activity on master regarding extlinux, worth investigating.


###
### Jumpstart config;
###   - booting the device after resetting original firmware, via android update + aml_autoscript.zip on sd
###   - sd boots using boot.ini + u-boot.ext from balbes150 if standard/update/regular boot
###   - sd boots using bootsector if emmc is zeroed out, I never tried this actually yet.
###   - sd boots kernel determined by {CHOSEN_EXTLINUX_JUMPSTART} - can be balbes150 kernel or armbian-built kernel
###   - sd boots using some DTB that can be balbes150 or anything else produced by armbian build, or custom binary one
###   - after first sd boot, flash_emmc.sh can be used to flash the emmc, also allowing for balbe or own kernel, dtb, etc.

# Extra kernel cmdline parameters to add to SD and to eMMC. Used by cloud-init to determine type of boot.
# Notice: in this fragment it is implemented via templating on extlinux.conf and variants.
#         if you're *also* using the cloud-init module it will use the same vars for convenience.
export KERNEL_EXTRA_CMDLINE_SD="oldskool.boottype=sd"              # Extra kernel cmdline to add to jumpstart/sd boot, before flashing to eMMC.
export KERNEL_EXTRA_CMDLINE_EMMC="oldskool.boottype=emmc"          # Extra kernel cmdline to add to emmc boot, after jumpstart.

### The jumpstart binary package ID. We use balbes150's last known good binary build.
export JUMPSTART_ID="5.9.0-arm-64-balbeslast"                      # This is the .tar.xz containing the binaries from balbe150's last built. If this does not exist it will be ignored. Needed if you need to boot balbes150 kernel.

### This will be the DTB used *during* jumpstart (boot from SD) and should be a balbe150 dtb in the overlays.
export JUMPSTART_DTB="tvbox/t95z-plus-meson-gxm-q200-giga-eth.dtb" # Use the q200+n1+eth DTB so we can write to eMMC after booting from SD. Damn shared GPIOs
# @TODO: a better example?

### The balbes150 bootsector that will be installed on the start of the SD card for jumpstart.
export JUMPSTART_SD_BOOTSECTOR="balbe_bootloader_sd_4mb.img"
display_alert "A very mysterious u-boot (?) build by @balbes150 -- help me find the sources!" "${JUMPSTART_SD_BOOTSECTOR}" "wrn"

### The balbes150 second-stage u-boot that will be installed as u-boot.ext on the SD jumpstart
# If I understand correctly, this is the second-stage u-boot that delegates to extlinux
export JUMPSTART_UBOOT="u-boot-s905x-s912" # theres others there. check.
display_alert "A very mysterious u-boot second-stage extlinux (?) build by @balbes150 -- help me find the sources!" "${JUMPSTART_UBOOT}" "wrn"

### Which extlinux, and thus, which kernel, to use for each phase (jumpstart on sd/emmc) -- you can mix and match.
#export CHOSEN_EXTLINUX_JUMPSTART="extlinux-jumpstart-balbe.conf"        # Balbes known last build for SD jumpstart...
export CHOSEN_EXTLINUX_JUMPSTART="extlinux-jumpstart-built-kernel.conf" # Own built kernel for SD jumpstart.
export CHOSEN_EXTLINUX_EMMC="extlinux-emmc-built-kernel.conf"           # Own built kernel for eMMC final target.

# This specific board has a binary known-good eMMC bootloader image, from original Android firmware.
# Set to "use_current_emmc_bootloader" (literally) if you have a working eMMC bootloader and want to keep that.
# Note: if you have booted CoreELEC, it has mucked with the bootloader, and your system won't be able to boot.
# Flash the original Android Firmware first then use the SD jumpstart card.
# Understand: if you don't have the exact hardware, using a given bootloader (instead of use_current_emmc_bootloader)
#             image will BRICK YOUR BOX.
#             I use this so I can switch from CoreELEC (on SD) to Armbian on eMMC without re-flashing Android.
export EMMC_KNOWN_GOOD_BOOTLOADER_EMMC="use_current_emmc_bootloader"

# These boards need to boot from an UUID... not LABEL=xx
export SD_ROOT_DEV_UUID="11111111-1111-1111-1111-111111111111"
export SD_ROOT_DEV="UUID=${SD_ROOT_DEV_UUID}"

# last chance to modify mkopts and such, add labels to partitions
prepare_partitions_custom__add_uuid_to_rootfs() {
	display_alert "prepare_partitions_custom adding to mfks ext4" "-U ${SD_ROOT_DEV_UUID}" "info"
	mkopts[ext4]="-U ${SD_ROOT_DEV_UUID} ${mkopts[ext4]}"
}

user_config__decompress_balbes_blobs() {
	[[ ! -f "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/balbe_bootloader_sd_4mb.img" ]] &&
		unxz -k "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/balbe_bootloader_sd_4mb.img.xz"

	[[ ! -f "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/t95z_working_uboot.img" ]] &&
		unxz -k "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/t95z_working_uboot.img.xz"

	[[ ! -f "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/t95z_android_recover.img" ]] &&
		unxz -k "$USERPATCHES_PATH/overlay/jumpstart/sd-root-root/t95z_android_recover.img.xz"
}

image_tweaks_pre_customize__add_balbes_uboot() {
	##### # Expand the binaries.
	##### # Right now there is a 50mb blob of balbes150's last working build.
	##### # This should be replaced with a torrent download or something like that.
	##### # Also if you respect the layout you can use any other kernel/initrd/uboot combination that works for your board.
	JUMPSTART_BINARY_TARBALL="$USERPATCHES_PATH/overlay/jumpstart/${JUMPSTART_ID}.tar.xz"
	if [[ -f "${JUMPSTART_BINARY_TARBALL}" ]]; then
		display_alert "Expanding binary pack" "${JUMPSTART_BINARY_TARBALL}" "info"
		PRE_PWD="$(pwd)" cd "$USERPATCHES_PATH/overlay/jumpstart" || exit 1
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
	mv "${SDCARD}"/boot/armbianEnv.txt "${SDCARD}"/boot/preJumpstart_armbianEnv.txt || true

	echo "... processing jumpstart templates ..."
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-emmc-built-kernel.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-emmc-built-kernel.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-jumpstart-balbe.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-jumpstart-balbe.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/extlinux/extlinux-jumpstart-built-kernel.conf | process_jumpstart_template >"${SDCARD}"/boot/extlinux/extlinux-jumpstart-built-kernel.conf
	cat "${USERPATCHES_PATH}"/overlay/jumpstart/sd-root-root/flash_emmc.sh | process_jumpstart_template >"${SDCARD}"/root/flash_emmc.sh
	# @TODO: idea, extlinux boot CoreElec Armlogic-ng or even CoreElec ce19 ?! why not...


	chmod +x "${SDCARD}"/root/flash_emmc.sh

	echo ".... will use ${CHOSEN_EXTLINUX_JUMPSTART} for jumpstart ..."
	cp "${SDCARD}/boot/extlinux/${CHOSEN_EXTLINUX_JUMPSTART}" "${SDCARD}"/boot/extlinux/extlinux.conf

	cp -r "${USERPATCHES_PATH}"/overlay/jumpstart/sd-boot/autoscripts "${SDCARD}"/boot/

	display_alert "Compiling aml scripts" "${SDCARD}/boot/autoscripts/" "info"
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/aml_autoscript.txt "${SDCARD}"/boot/aml_autoscript.orig
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/emmc_autoscript.txt "${SDCARD}"/boot/emmc_autoscript
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/sd_autoscript.txt "${SDCARD}"/boot/sd_autoscript
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/s905_autoscript.txt "${SDCARD}"/boot/s905_autoscript
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/ce_boot_from_emmc.txt "${SDCARD}"/boot/ce_boot_from_emmc
	mkimage -A arm -O linux -T script -C none -d "${SDCARD}"/boot/autoscripts/sd_autoscript.txt "${SDCARD}"/boot/aml_autoscript
	display_alert "Done compiling aml scripts" "${SDCARD}/boot/autoscripts/" "info"

	echo ".... creating aml_autoscript.zip ...."
	echo "fake zip for for android to boot from this sd card" >"${SDCARD}"/boot/aml_autoscript.zip

	# for sure boot.cmd and boot.scr are not used, at least for s912
	rm -f "${SDCARD}"/boot/boot.cmd "${SDCARD}"/boot/boot.scr "${SDCARD}"/boot/boot.bmp

	#@ TODO: what about boot.ini ???

	# balbe150 provides 3 variations of u-boot, configure in <board>.conf
	cp "${SDCARD}/boot/${JUMPSTART_UBOOT}" "${SDCARD}"/boot/u-boot.ext

}

## Internal functions

# process template from stdin to stdout using the vars
process_jumpstart_template() {
	cat - |
		awk "{gsub(\"@@EMMC_KNOWN_GOOD_BOOTLOADER_EMMC@@\",\"${EMMC_KNOWN_GOOD_BOOTLOADER_EMMC}\"); print}" |
		awk "{gsub(\"@@KERNEL_EXTRA_CMDLINE_SD@@\",\"${KERNEL_EXTRA_CMDLINE_SD}\"); print}" |
		awk "{gsub(\"@@KERNEL_EXTRA_CMDLINE_EMMC@@\",\"${KERNEL_EXTRA_CMDLINE_EMMC}\"); print}" |
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
