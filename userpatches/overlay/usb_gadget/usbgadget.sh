#!/bin/sh

PREREQ=""
case $1 in
prereqs)
	echo "$PREREQ"
	exit 0
	;;
esac

deviceinfo_name="OnePlus 5"
deviceinfo_manufacturer="OnePlus"
usb_idVendor="0x18D1"  # Google Inc.
usb_idProduct="0xD001" # Nexus 4 (fastboot)
usb_serialnumber="Armbian"

clear
echo "ONEPLUS ANDROID usbgadget BRINGUP START"
sleep 5

echo "Mount configfs in 1s.."
sleep 1

mkdir -p /config
mount -t configfs -o nodev,noexec,nosuid configfs /config

CONFIGFS=/config/usb_gadget

if ! [ -e "$CONFIGFS" ]; then
	echo "  /config/usb_gadget does not exist, skipping configfs usb gadget"
	sleep 5
	return
fi

echo "  Setting up an USB gadget through configfs"
mkdir $CONFIGFS/g1 || echo "  Couldn't create $CONFIGFS/g1"
echo "$usb_idVendor" >"$CONFIGFS/g1/idVendor"
echo "$usb_idProduct" >"$CONFIGFS/g1/idProduct"

# Create english (0x409) strings
mkdir $CONFIGFS/g1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/strings/0x409"

echo "$deviceinfo_manufacturer" >"$CONFIGFS/g1/strings/0x409/manufacturer"
echo "$usb_serialnumber" >"$CONFIGFS/g1/strings/0x409/serialnumber"
echo "$deviceinfo_name" >"$CONFIGFS/g1/strings/0x409/product"

# Create configuration instance
mkdir $CONFIGFS/g1/configs/c.1 || echo "  Couldn't create $CONFIGFS/g1/configs/c.1"

## ACM device

echo "Create ACM device"
# Create serial/acm function.
mkdir $CONFIGFS/g1/functions/acm.usb0 || echo "  Couldn't create $CONFIGFS/g1/functions/acm.usb0"

# Link the serial instance to the configuration
ln -s $CONFIGFS/g1/functions/acm.usb0 $CONFIGFS/g1/configs/c.1 || echo "  Couldn't symlink acm.usb0"

## RNDIS (Network)

# Create rndis function.
mkdir $CONFIGFS/g1/functions/rndis.usb0 || echo "  Couldn't create $CONFIGFS/g1/functions/rndis.usb0"

mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
echo "rndis" >$CONFIGFS/g1/configs/c.1/strings/0x409/configuration || echo "  Couldn't write configuration name"

# Link the rndis instance to the configuration
ln -s $CONFIGFS/g1/functions/rndis.usb0 $CONFIGFS/g1/configs/c.1 || echo "  Couldn't symlink rndis.usb0"

echo "Done creating functions and configs, going for the UDC.."

# Check if there's an USB Device Controller
if [ -z "$(ls /sys/class/udc)" ]; then
	echo "  No USB Device Controller available"
	sleep 5
	return
fi

# Link the gadget instance to an USB Device Controller. This activates the gadget.
# See also: https://github.com/postmarketOS/pmbootstrap/issues/338
# shellcheck disable=SC2005
echo "$(ls /sys/class/udc)" >$CONFIGFS/g1/UDC || echo "  Couldn't write UDC"

umount /config

echo "Done Android USB bringup"
sleep 30

echo "Exiting ANDROID usbgadget hook"
