# @TODO: use decent var names. early ones were rips from pmOS. (or: just curl/source the deviceinfo from there)

# @TODO: document the usb gadget with example cmdlines for the host, like
# ifconfig usb0 up 172.16.42.2 netmask 255.255.255.0; sysctl net.ipv4.ip_forward=1; iptables -P FORWARD ACCEPT; iptables -A POSTROUTING -t nat -j MASQUERADE -s 172.16.42.0/24

pre_customize_image__inject_initramfs_usb_gadget() {
	local script_file_src="${FRAGMENT_DIR}/init-premount/usbgadget.sh"
	local script_file_dst="${SDCARD}/etc/initramfs-tools/scripts/init-premount/usbgadget.sh"
	cp "${script_file_src}" "${script_file_dst}"
	chmod +x "${script_file_dst}"
}

user_config__add_avahi_daemon() {
	export PACKAGE_LIST_ADDITIONAL="${PACKAGE_LIST_ADDITIONAL} avahi-daemon"
}

config_tweaks_post_family_config__use_usb_gadget_serial_as_console() {
	export SERIALCON="ttyGS0" # This is a serial USB gadget that will be setup by the initramfs, after kernel booted, but before switching into rootfs.
}

# this is a hook for the cloud-init fragment. which is not even here ($SRC/fragments) yet 
# (it sits on rpardini's userpatches/fragments). and that is fine. this function will never be called.
# @TODO: the fragment manager should warn us about that to avoid losing your mind when things dont work. 
cloud_init_determine_network_config_template__prefer_usb0_static() {
	# Default to using usb0 with a static IP. effectively no networking, but the user can access it via ssh.
	# If user goes all the way, they can set up dnsmasq/iptables etc to forward traffic to the internet.
	# But then it probably is easier to just bridge hosts eth0 and usb0 together and use usb0-dhcp.
	export CLOUD_INIT_NET_CONFIG_FILE="usb0-staticip"
	display_alert "c-i network-config" "${CLOUD_INIT_NET_CONFIG_FILE}" "info"
}

