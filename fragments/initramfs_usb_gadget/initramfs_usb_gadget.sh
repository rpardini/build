
# @TODO: document the usb gadget with example cmdlines for the host, like
# ifconfig usb0 up 172.16.42.2 netmask 255.255.255.0; sysctl net.ipv4.ip_forward=1; iptables -P FORWARD ACCEPT; iptables -A POSTROUTING -t nat -j MASQUERADE -s 172.16.42.0/24

config_pre_customize_image__inject_initramfs_usb_gadget() {
	display_alert "Custom config stage" "config_pre_customize_image__inject_initramfs_usb_gadget" "info"
	local script_file_src="${FRAGMENT_DIR}/init-premount/usbgadget.sh"
	local script_file_dst="${SDCARD}/etc/initramfs-tools/scripts/init-premount/usbgadget.sh"
	cp "${script_file_src}" "${script_file_dst}"
	chmod +x "${script_file_dst}"
}

user_config__add_avahi_daemon() {
	display_alert "Custom config stage" "user_config__add_avahi_daemon" "info"
	export PACKAGE_LIST_ADDITIONAL="${PACKAGE_LIST_ADDITIONAL} avahi-daemon"
}

config_tweaks_post_family_config__use_usb_gadget_serial_as_console() {
	export SERIALCON="ttyGS0" # This is a serial USB gadget that will be setup by the initramfs, after kernel booted, but before switching into rootfs.
}
