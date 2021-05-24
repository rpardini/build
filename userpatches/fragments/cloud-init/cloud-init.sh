source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

# This fragment enables cloud-init.
# As a side effect it removes NetworkManager and replaces it with netplan.io and the systemd/networkd renderer.
# It sets up in a way that the user-data, meta-data and network-config reside in /boot (CLOUD_INIT_CONFIG_LOCATION)
# it can be used to setup users, passwords, ssh keys, install packages, install and delegate to ansible, etc.
# cloud providers allow setting user-data, but provide network-config and meta-data themselves; here we try

# Config for cloud-init.
export SKIP_CLOUD_INIT_CONFIG="no"        # if yes, installs but does not configure anything.
export CLOUD_INIT_USER_DATA_URL="files"   # "files" to use config files, or an URL to go straight to it
export CLOUD_INIT_CONFIG_LOCATION="/boot" # where on the sdcard c-i will look for user-data, network-config, meta-data files

# Default to using e* devices with dhcp, but not wait for them, so user-data needs to be local-only
# Change to eth0-dhcp-wait to use https:// includes in user-data, or to something else for non-ethernet devices
export CLOUD_INIT_NET_CONFIG_FILE="eth0-dhcp"

pre_umount_final_image__300_prepare_cloud_init_startup() {
	# remove any networkd config leftover from armbian build
	rm -f "${CI_TARGET}"/etc/systemd/network/*.network || true

	# cleanup -- cloud-init makes some Armbian stuff actually get in the way
	[[ -f "${CI_TARGET}/boot/armbian_first_run.txt.template" ]] && rm -f "${CI_TARGET}/boot/armbian_first_run.txt.template"
	[[ -f "${CI_TARGET}/root/.not_logged_in_yet" ]] && rm -f "${CI_TARGET}/root/.not_logged_in_yet"

	# if disabled skip configuration
	[[ "${SKIP_CLOUD_INIT_CONFIG}" == "yes" ]] && return 0

	display_alert "Configuring cloud-init at" "${CLOUD_INIT_CONFIG_LOCATION}" "info"

	local CI_TARGET="${MOUNT}"

	cp "${FRAGMENT_DIR}"/config/cloud-cfg.yaml "${CI_TARGET}"/etc/cloud/cloud.cfg.d/99-armbian-boot.cfg

	# Learn how Ubuntu does things by reading lxd docs...:
	# https://lxd.readthedocs.io/en/latest/cloud-init

	cp "${FRAGMENT_DIR}"/config/meta-data.yaml "${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/meta-data
	echo -e "\n\ninstance-id: armbian-${BOARD}" >>"${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/meta-data

	cp "${FRAGMENT_DIR}"/config/user-data.yaml "${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/user-data

	# This module has hook points, just like the regular Armbian build system. So fragments can influence other fragments. Neat?
	# In this case, fragments compete to modify CLOUD_INIT_NET_CONFIG_FILE, so the ordering of the hooks is extremely important.
	[[ $(type -t cloud_init_determine_network_config_template) == function ]] && cloud_init_determine_network_config_template

	# Hack, some wierd bug with c-i causes "match:" devices to not be brought up.
	# For now just don't write a default network-config, c-i's default/fallback detection will dhcp it anyway (and that works).
	if [[ ${CLOUD_INIT_NET_CONFIG_FILE} == *"eth0-dhcp"* ]]; then
		display_alert "dhcp-variant (${CLOUD_INIT_NET_CONFIG_FILE})" "written as ${CLOUD_INIT_CONFIG_LOCATION}/network-config.sample" ""
		cp "${FRAGMENT_DIR}"/config/network-configs/${CLOUD_INIT_NET_CONFIG_FILE}.yaml "${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/network-config.sample
	else
		display_alert "Using network-config" "network-configs/${CLOUD_INIT_NET_CONFIG_FILE}.yaml" "info"
		cp "${FRAGMENT_DIR}"/config/network-configs/${CLOUD_INIT_NET_CONFIG_FILE}.yaml "${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/network-config
	fi

	# overwrite default (user-oriented) user-data with direct #include via CLOUD_INIT_USER_DATA_URL (automation oriented)
	if [[ "a${CLOUD_INIT_USER_DATA_URL}" != "afiles" ]]; then
		display_alert "Cloud-init user-data points directly to" "${CLOUD_INIT_USER_DATA_URL}" "wrn"
		echo -e "#include\n${CLOUD_INIT_USER_DATA_URL}" >"${CI_TARGET}${CLOUD_INIT_CONFIG_LOCATION}"/user-data
	fi

	# Configure logging for cloud-init. INFO is too little and DEBUG too much (as always)
	cp "${FRAGMENT_DIR}"/config/debug_logging.yaml "${CI_TARGET}"/etc/cloud/cloud.cfg.d/05_logging.cfg

	# seed the /var/lib/cloud/seed/nocloud directory with symlinks to ${CLOUD_INIT_CONFIG_LOCATION}/*-data|config
	# symlinks always there, be dangling or not.
	local seed_dir="${CI_TARGET}"/var/lib/cloud/seed/nocloud
	mkdir -p "${seed_dir}"
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/network-config" "${seed_dir}"/network-config
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/user-data" "${seed_dir}"/user-data
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/meta-data" "${seed_dir}"/meta-data
}

# not so early hook
user_config__enable_cloudinit() {
	CLOUD_INIT_PKGS="cloud-init cloud-initramfs-growroot eatmydata curl tree netplan.io"
	EXTRA_WANTED_PACKAGES="lvm2 thin-provisioning-tools" # networkd-dispatcher

	# Release specific packages
	export DEBOOTSTRAP_COMPONENTS="main,universe"

	# Replace ifupdown with netplan during debootstrap.
	export DEBOOTSTRAP_LIST="${DEBOOTSTRAP_LIST//ifupdown/netplan.io}"

	# Enable cloud-init; this changes bring-up process radically.
	export PACKAGE_LIST="${PACKAGE_LIST} ${EXTRA_WANTED_PACKAGES} ${CLOUD_INIT_PKGS}"

	# Remove hostapd. Its a cloud-like image, not an access point.
	# Note WPA-supplicant can still be used via network-config... but only as a client.
	# Remove more end-user oriented stuff.
	remove_packages_everywhere network-manager-openvpn network-manager hostapd ifenslave resolvconf ifupdown vnstat

	# PACKAGE_LIST_BOARD_REMOVE runs apt-get remove later during the build. Useful if no other way to remove.
	#export PACKAGE_LIST_BOARD_REMOVE="${PACKAGE_LIST_BOARD_REMOVE} hostapd ifupdown"
}

user_config_post_aggregate_packages__900_confirm_cloudinit_packages() {
	# Make sure the package aggregation is not insane / changed too much
	# by checking that the final PACKAGE_LIST contains 'cloud-init' and 'netplan.io'
	if [[ ${PACKAGE_LIST} == *"cloud-init"* ]]; then
		display_alert "Package found OK." "cloud-init"
	else
		display_alert "Package not found in package list." "cloud-init" "wrn"
		read
	fi

	# could be nice checking that network-manager is NOT there too
	if [[ ${PACKAGE_LIST} == *"network-manager"* ]]; then
		display_alert "Package found in package list -- should not be!" "network-manager" "wrn"
	else
		display_alert "Package not being installed" "network-manager"
	fi

}

config_post_debootstrap_tweaks__restore_systemd_resolved_from_resolvconf_and_armbian() {
	# do away with the resolv.conf leftover in the image.
	# set up systemd-resolved which is the way cloud images generally work
	rm -f "${SDCARD}"/etc/resolv.conf
	ln -s ../run/systemd/resolve/stub-resolv.conf "${SDCARD}"/etc/resolv.conf
}

config_pre_install_distribution_specific__preserve_pristine_etc_systemd() {
	# Preserve some stuff from systemd that Armbian build will touch. This way we can let armbian do its thing
	# and then just revert back to the preserved state.
	cp -rp "${SDCARD}"/etc/systemd "${SDCARD}"/etc/systemd.orig
}

pre_customize_image__restore_preserved_systemd_and_netplan_stuff() {
	# Restore some stuff we preserved in config_pre_install_distribution_specific()
	cp -p "${SDCARD}"/etc/systemd.orig/journald.conf "${SDCARD}"/etc/systemd/journald.conf
	cp -p "${SDCARD}"/etc/systemd.orig/resolved.conf "${SDCARD}"/etc/systemd/resolved.conf

	# Remove the preserved dir
	rm -rf "${SDCARD}"/etc/systemd.orig || true

	# Clean netplan config. Cloud-init will create its own.
	rm -f "${SDCARD}"/etc/netplan/armbian-default.yaml
}

pre_umount_final_image__200_add_ci_suffix_to_version() {
	export version="${version}-cloud"
	if [[ "a${CLOUD_INIT_USER_DATA_URL}" != "afiles" ]]; then
		export version="${version}-custom-userdata"
	fi
	display_alert "Cloud-init setting version to" "${version}" "wrn"
}
