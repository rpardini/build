#! /bin/bash

# this was originally install-aml.sh from balbe150

# Script will stop at the first sign of errors, except pipes
set -e

# Uncomment this to debug
# set -x

logger_termopt="-Txterm-256color"
logger_bold="$(tput ${logger_termopt} bold)"
logger_normal="$(tput ${logger_termopt} sgr0)"

display_msg() {
	echo "${logger_normal}--> ${logger_bold}$@${logger_normal}"
}

DATE_ID=$(date +"%d_%m_%Y_%H_%M_%S")

export BOARD_NAME="t95z plus"                              # maybe: "@@BOARD_NAME@@"
export GOOD_BOOT="t95z_working_uboot.img"                  # maybe: "@@EMMC_KNOWN_GOOD_BOOTLOADER_EMMC@@"
export THE_EXTLINUXT_MMC="extlinux-emmc-built-kernel.conf" # maybe: "@@CHOSEN_EXTLINUX_EMMC@@"
export EXT4_RESTORE="/root/rootfs.ext4.img"

GOOD_UBOOT_EMMC_FILE="/root/${GOOD_BOOT}"
UBOOT_BACKUP_FILE="/root/u-boot-default-aml-${DATE_ID}.img"
[[ ! -f ${GOOD_UBOOT_EMMC_FILE} ]] && GOOD_UBOOT_EMMC_FILE="${UBOOT_BACKUP_FILE}"

DO_BOOT=yes
DO_ROOT=yes

display_msg "Start script create MBR and filesystem"

hasdrives=$(lsblk | grep -oE '(mmcblk[0-9])' | sort | uniq)
if [ "$hasdrives" = "" ]; then
	echo "UNABLE TO FIND ANY EMMC OR SD DRIVES ON THIS SYSTEM!!! "
	exit 1
fi
avail=$(lsblk | grep -oE '(mmcblk[0-9]|sda[0-9])' | sort | uniq)
if [ "$avail" = "" ]; then
	echo "UNABLE TO FIND ANY DRIVES ON THIS SYSTEM!!!"
	exit 1
fi
runfrom=$(lsblk | grep /$ | grep -oE '(mmcblk[0-9]|sda[0-9])')
if [ "$runfrom" = "" ]; then
	echo " UNABLE TO FIND ROOT OF THE RUNNING SYSTEM!!! "
	exit 1
fi
emmc=$(echo $avail | sed "s/$runfrom//" | sed "s/sd[a-z][0-9]//g" | sed "s/ //g")
if [ "$emmc" = "" ]; then
	echo " UNABLE TO FIND YOUR EMMC DRIVE OR YOU ALREADY RUN FROM EMMC!!!"
	exit 1
fi
if [ "$runfrom" = "$avail" ]; then
	echo " YOU ARE RUNNING ALREADY FROM EMMC!!! "
	exit 1
fi
if [ $runfrom = $emmc ]; then
	echo " YOU ARE RUNNING ALREADY FROM EMMC!!! "
	exit 1
fi
if [ "$(echo $emmc | grep mmcblk)" = "" ]; then
	echo " YOU DO NOT APPEAR TO HAVE AN EMMC DRIVE!!! "
	exit 1
fi

EMMC_INFO_UDEV=$(udevadm info -a /dev/${emmc} | grep -e "ATTRS{name}" -e "ATTRS{date}" -e "ATTRS{serial}" -e "ATTRS{rca}" | cut -d "\"" -f 2 | xargs echo)
EMMC_INFO_DMESG=$(dmesg | grep "${emmc}\:" | head -1 | cut -d ":" -f 3)

SD_INFO_UDEV=$(udevadm info -a /dev/${runfrom} | grep -e "ATTRS{name}" -e "ATTRS{date}" -e "ATTRS{serial}" -e "ATTRS{rca}" | cut -d "\"" -f 2 | xargs echo)
SD_INFO_DMESG=$(dmesg | grep "${runfrom}\:" | head -1 | cut -d ":" -f 3)

echo "------------------------------------"
echo "Flash to eMMC info for '${BOARD_NAME}'"
echo "------------------------------------"
echo "Will deploy extlinux        : ${THE_EXTLINUXT_MMC}"
echo "Saved current bootloader to : ${UBOOT_BACKUP_FILE}"
echo "Will restore bootloader from: ${GOOD_BOOT}"
echo "rootfs ext4 restore from    : ${EXT4_RESTORE}"
echo "------------------------------------"
echo "Found eMMC target: ${emmc}"
echo "             udev: ${EMMC_INFO_UDEV}"
echo "            dmesg: ${EMMC_INFO_DMESG}"
echo "------------------------------------"
echo "Jumpstart from SD: ${runfrom}"
echo "             udev: ${SD_INFO_UDEV}"
echo "            dmesg: ${SD_INFO_DMESG}"
echo "------------------------------------"
echo ""
echo -n "ENTER to continue, or Ctrl-C to abort: "
read

DEV_EMMC="/dev/$emmc"

display_msg "Start backup u-boot default to file ${UBOOT_BACKUP_FILE}"

# @TODO: try to name the file according to some hw identifier?
dd if="${DEV_EMMC}" of="${UBOOT_BACKUP_FILE}" bs=1M count=4
display_msg "Done backup u-boot default to file ${UBOOT_BACKUP_FILE}"

# @TODO: try to figure out if the bootloader dumped contains xxxELEC, maybe via 'strings'?

display_msg "Start create MBR and partition"

# understand: those numbers are relevant. 1gb space is enough for android recovery, etc, from original firmware
# to keep working. if we overwrite it too much bad stuff happens... so just waste 1.5gb of our emmc and be safe.
parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 1000M 1512M
parted -s "${DEV_EMMC}" mkpart primary ext4 1513M 100%

display_msg "Start restore u-boot: ${GOOD_BOOT}"

dd if="${GOOD_UBOOT_EMMC_FILE}" of="${DEV_EMMC}" conv=fsync bs=1 count=442
dd if="${GOOD_UBOOT_EMMC_FILE}" of="${DEV_EMMC}" conv=fsync bs=512 skip=1 seek=1

sync
sleep 1
partprobe "${DEV_EMMC}"
sleep 1
sync

display_msg "Done"

display_msg "Start copy system for eMMC."

mkdir -p /target_emmc_install
chmod 777 /target_emmc_install

PART_BOOT="${DEV_EMMC}p1"
PART_ROOT="${DEV_EMMC}p2"
DIR_INSTALL="/target_emmc_install/install"

if [ -d $DIR_INSTALL ]; then
	display_msg "Install dir ${DIR_INSTALL} already exists. Trouble. Exit."
	exit 1
fi

mkdir -p $DIR_INSTALL

if [[ "$DO_BOOT" == "yes" ]]; then

	if grep -q $PART_BOOT /proc/mounts; then
		display_msg "Unmounting BOOT partiton."
		umount -f $PART_BOOT
	fi
	display_msg "Formatting BOOT partition..."
	mkfs.vfat -n "BOOT_EMMC" $PART_BOOT
	display_msg "done formatting BOOT."

	mount -o rw $PART_BOOT $DIR_INSTALL

	display_msg "Copying BOOT..."
	cp -r /boot/* $DIR_INSTALL && sync
	display_msg "done copying BOOT."

	display_msg "Using ${THE_EXTLINUXT_MMC} as default on the eMMC boot partition."
	rm -rf $DIR_INSTALL/extlinux
	mkdir -p $DIR_INSTALL/extlinux
	cp /boot/extlinux/${THE_EXTLINUXT_MMC} $DIR_INSTALL/extlinux/extlinux.conf

	display_msg "--- <final extlinux>: ${THE_EXTLINUXT_MMC} ----"
	cat $DIR_INSTALL/extlinux/extlinux.conf
	display_msg "--- </final extlinux>: ${THE_EXTLINUXT_MMC} ---"

	display_msg "done extlinux config."

	display_msg "Installing u-boot.ext that is currently in use in the SD to the eMMC ..."
	cp -f $DIR_INSTALL/u-boot.ext $DIR_INSTALL/u-boot.emmc

	if [[ -f "$DIR_INSTALL/emmc.boot.ini.txt" ]]; then
		display_msg "Fixing boot.ini to emmc.boot.ini.txt. "
		cp -v "$DIR_INSTALL/emmc.boot.ini.txt" "$DIR_INSTALL/boot.ini"
	elif [[ -f "$DIR_INSTALL/boot.ini" ]]; then
		display_msg "Fixing boot.ini to point to new u-boot.emmc. "
		sed -e "s/u-boot.ext/u-boot.emmc/g" -i "$DIR_INSTALL/boot.ini"
		display_msg "done u-boot juggles."
	else
		display_msg "Nothing to be done about boot.ini. I hope."
	fi

	# Clean jumpstart kernel-stuff.
	rm -rf $DIR_INSTALL/0-* || true

	# Other cleanings
	[[ -f $DIR_INSTALL/boot.cmd ]] && rm -f $DIR_INSTALL/boot.cmd
	[[ -f $DIR_INSTALL/boot.scr ]] && rm -f $DIR_INSTALL/boot.scr

	sync
	umount $DIR_INSTALL
	display_msg "Done /boot p1 stuff."
fi

if [[ "$DO_ROOT" == "yes" ]]; then

	if grep -q $PART_ROOT /proc/mounts; then
		display_msg "Unmounting ROOT partiton."
		umount -f $PART_ROOT
	fi

	display_msg "Restoring rootfs '${EXT4_RESTORE}' to '$PART_ROOT'"

	# flash-optimized version
	e2image -racp ${EXT4_RESTORE} $PART_ROOT

	# direct restore via dd
	#display_msg "pv ${EXT4_RESTORE} | dd of=$PART_ROOT bs=1M "
	#pv ${EXT4_RESTORE} | dd of=$PART_ROOT bs=1M

	display_msg "Done restore!"

	display_msg "Sync..." && sync && display_msg "Sync done!"
	sleep 5
	display_msg "Partprobe..." && partprobe ${DEV_EMMC} && display_msg "Partprobe done!"

	sync

	display_msg "Sync..." && sync && display_msg "Sync done!"
	e2fsck -f -y $PART_ROOT
	sleep 5

	display_msg "Sync..." && sync && display_msg "Sync done!"
	resize2fs -p $PART_ROOT
	sleep 5

	display_msg "Sync..." && sync && display_msg "Sync done!"
	display_msg "Tuning fs parameters..."
	tune2fs -U 66666666-6666-6666-6666-666666666666 -L ROOT_EMMC $PART_ROOT
	sleep 5

	display_msg "Sync..." && sync && display_msg "Sync done!"
	mount -o rw $PART_ROOT $DIR_INSTALL

	display_msg "Sync..." && sync && display_msg "Sync done!"

	display_msg "Installing new fstab to emmc root..."

	[[ -f $DIR_INSTALL/etc/fstab ]] && rm $DIR_INSTALL/etc/fstab
	cp -a /root/fstab.emmc $DIR_INSTALL/etc/fstab

	# Cleanup after ourselves.
	rm -f $DIR_INSTALL/root/flash_emmc.sh || true
	[[ -f $DIR_INSTALL/root/fstab.emmc ]] && rm $DIR_INSTALL/root/fstab.emmc

	sync
	umount $DIR_INSTALL
	display_msg "Done root stuff"
fi

rm -rf /target_emmc_install
sync

display_msg "*******************************************"
display_msg "Complete copy OS to eMMC "
display_msg "*******************************************"

display_msg "Done."

display_msg "Shutdown, remove the SD and reboot to boot from eMMC. Hopefully."
