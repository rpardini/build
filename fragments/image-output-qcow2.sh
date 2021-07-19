# Config

# Hooks

# Early check for host-side tools needed.
# This could benefit from a new hook_point "do_prepare_host" that actually allowed us to install them
user_config__200_qemu_host_tools_installed() {
	if [[ ! -f /usr/bin/qemu-img ]]; then
		display_alert "Missing QEMU tools needed for qcow2 images" "Install with: apt install -y qemu-utils" "err"
		# @TODO: Armbian exit_with_?
		exit 3 # Hopefully abort the build.
	else
		display_alert "QEMU tooling" "ok" "info"
	fi
}

# Zerofree the image early after umounting it
config_post_umount_final_image__200_zerofree() {
	display_alert "Zerofreeing image" "image-output-qcow2" "info"
	zerofree -v "${LOOP}p2" || true # @TODO: does it work?
}

post_build_image__900_convert_to_qcow2_img() {
	# Can't zerofree here, zerofree needs a loopback not a file.
	display_alert "Converting image to qcow2" "image-output-qcow2" "info"
	qemu-img convert -f raw -O qcow2 ${FINALDEST}/${version}.img ${FINALDEST}/${version}.img.qcow2
}
