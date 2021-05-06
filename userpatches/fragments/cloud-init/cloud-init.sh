# This fragment enables cloud-init.
# As a side effect it removes NetworkManager and replaces it with netplan.io and the systemd/networkd renderer.
# It sets up in a way that the user-data, meta-data and network-config reside in /boot (CLOUD_INIT_CONFIG_LOCATION)
# it can be used to setup users, passwords, ssh keys, install packages, install and delegate to ansible, etc.
# cloud providers allow setting user-data, but provide network-config and meta-data themselves; here we try

# Config for cloud-init.
export CLOUD_INIT_USER_DATA_URL="files"   # "files" to use config files, or an URL to go straight to it
export CLOUD_INIT_CONFIG_LOCATION="/boot" # where on the sdcard c-i will look for user-data, network-config, meta-data files

# Default to using e* devices with dhcp, but not wait for them, so user-data needs to be local-only
# Change to eth0-dhcp-wait to use https:// includes in user-data, or to something else for non-ethernet devices
export CLOUD_INIT_NET_CONFIG_FILE="eth0-dhcp"

# Extra kernel cmdline parameters to add to SD and to eMMC. Used by cloud-init to determine type of boot.
# Notice: in this fragment it is implemented as hacks to armbianEnv.txt;
#         if you're *also* using the jumpstart module, it will use the same vars via extlinux.conf boot, for convenience.
export KERNEL_EXTRA_CMDLINE_SD="oldskool.boottype=sd"     # Extra kernel cmdline to add to jumpstart/sd boot, before flashing to eMMC.
export KERNEL_EXTRA_CMDLINE_EMMC="oldskool.boottype=emmc" # Extra kernel cmdline to add to emmc boot, after jumpstart.

# enable for debugging, package list assembly can be confusing.
export DEBUG_PACKAGE_LISTS=false

# This runs after install_common() and chroot_installpackages_local()
# Inside customize_image(), before running the actual custom script.
# We dont use the custom script so actual image customization is done here
# not clear what happens after this? see below
image_tweaks_pre_customize__cloud_init() {
	echo -e "# configure cloud-init for NoCloud\ndatasource_list: [ NoCloud, None ]\ndatasource:\n  NoCloud: \n    dsmode: local\n    seedfrom: /boot/" >>"${SDCARD}"/etc/cloud/cloud.cfg.d/99-armbian.cfg

	cp "${FRAGMENT_DIR}"/config/meta-data.yaml "${SDCARD}${CLOUD_INIT_CONFIG_LOCATION}"/meta-data
	echo -e "\n\ninstance-id: armbian-${BOARD}" >>"${SDCARD}${CLOUD_INIT_CONFIG_LOCATION}"/meta-data

	cp "${FRAGMENT_DIR}"/config/user-data.yaml "${SDCARD}${CLOUD_INIT_CONFIG_LOCATION}"/user-data

	# This module has hook points, just like the regular Armbian build system. So fragments can influence other fragments. Neat?
	# In this case, fragments compete to modify CLOUD_INIT_NET_CONFIG_FILE, so the ordering of the hooks is extremely important.
	[[ $(type -t cloud_init_determine_network_config_template) == function ]] && cloud_init_determine_network_config_template
	display_alert "Using network-config (final)" "network-configs/${CLOUD_INIT_NET_CONFIG_FILE}.yaml" "info"

	cp "${FRAGMENT_DIR}"/config/network-configs/${CLOUD_INIT_NET_CONFIG_FILE}.yaml "${SDCARD}${CLOUD_INIT_CONFIG_LOCATION}"/network-config

	# overwrite default (user-oriented) user-data with direct #include via CLOUD_INIT_USER_DATA_URL (automation oriented)
	if [[ "a${CLOUD_INIT_USER_DATA_URL}" != "afiles" ]]; then
		display_alert "Cloud-init user-data points directly to" "${CLOUD_INIT_USER_DATA_URL}" "wrn"
		echo -e "#include\n${CLOUD_INIT_USER_DATA_URL}" >"${SDCARD}${CLOUD_INIT_CONFIG_LOCATION}"/user-data
	fi

	# hack, the fact is I really can't understand cloud-init "DataSourceNoCloud" and its relation to network-config.
	# seed the /var/lib/cloud/seed/nocloud directory with symlinks to ${CLOUD_INIT_CONFIG_LOCATION}/*-data|config
	local seed_dir="${SDCARD}"/var/lib/cloud/seed/nocloud
	mkdir -p "${seed_dir}"
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/user-data" "${seed_dir}"/user-data
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/meta-data" "${seed_dir}"/meta-data
	ln -s "${CLOUD_INIT_CONFIG_LOCATION}/network-config" "${seed_dir}"/network-config

	# cleanup -- cloud-init makes some Armbian stuff actually get in the way
	[[ -f "${SDCARD}/boot/armbian_first_run.txt.template" ]] && rm -f "${SDCARD}/boot/armbian_first_run.txt.template"
	[[ -f "${SDCARD}/root/.not_logged_in_yet" ]] && rm -f "${SDCARD}/root/.not_logged_in_yet"
}

# not so early hook
user_config__enable_cloudinit() {
	CLOUD_INIT_PKGS="cloud-init cloud-initramfs-growroot eatmydata curl tree netplan.io"
	EXTRA_WANTED_PACKAGES="lvm2 thin-provisioning-tools nfs-common kbd networkd-dispatcher"

	# At this point, PACKAGE_LIST_RM is not processed yet, so we can use it to get rid of packages.
	# DEBOOTSTRAP_LIST has been calculated already though, we can still modify it directly.
	# DEBOOTSTRAP_LIST will be fed directly to debootstrap --include=

	# Release specific packages
	export DEBOOTSTRAP_COMPONENTS="main,universe"

	# Replace ifupdown with netplan during debootstrap.
	export DEBOOTSTRAP_LIST="${DEBOOTSTRAP_LIST//ifupdown/netplan.io} rng-tools fdisk"

	# Remove stuff that makes no sense with cloud-init
	# We could add to PACKAGE_LIST_ADDITIONAL here, it will be aggregated and processed later.

	# Add some packages I will install anyway via cloud-init and that will cause a new initramfs to be generated.
	# So we save a lot of time on first boot/first emmc flash
	# Enable cloud-init; this changes bring-up process radically.
	export PACKAGE_LIST_ADDITIONAL="${PACKAGE_LIST_ADDITIONAL} ${EXTRA_WANTED_PACKAGES} ${CLOUD_INIT_PKGS}"

	# Remove hostapd. Its a cloud-like image, not an access point.
	# Note WPA-supplicant can still be used via network-config... but only as a client.
	export PACKAGE_LIST_RM="hostapd network-manager ifenslave resolvconf ifupdown"

	# PACKAGE_LIST_BOARD_REMOVE runs apt-get remove later during the build. Useful if no other way to remove.
	export PACKAGE_LIST_BOARD_REMOVE="hostapd ifupdown"

	# Show lists:
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list DEBOOTSTRAP_LIST                      (final) " "${DEBOOTSTRAP_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST              (yet.to.be.aggrgtd) " "${PACKAGE_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_ADDITIONAL   (yet.to.be.aggrgtd) " "${PACKAGE_LIST_ADDITIONAL}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_BOARD_REMOVE (yet.to.be.aggrgtd) " "${PACKAGE_LIST_BOARD_REMOVE}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_RM           (yet.to.be.aggrgtd) " "${PACKAGE_LIST_RM}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_EXCLUDE      (yet.to.be.aggrgtd) " "${PACKAGE_LIST_EXCLUDE}" "info"

}

user_config_post_aggregate_packages__confirm_cloudinit_packages() {
	# echo "Fragment: HOOK_POINT:${HOOK_POINT} HOOK_POINT_FUNCTION:${HOOK_POINT_FUNCTION}"
	# echo "Fragment: FRAGMENT_DIR:${FRAGMENT_DIR}"
	# echo "Fragment: FRAGMENT_FILE:${FRAGMENT_FILE}"

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
		read
	else
		display_alert "Package not being installed" "network-manager"
	fi

	# Show lists:
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list DEBOOTSTRAP_LIST          (super-final)) " "${DEBOOTSTRAP_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST              (super-final)) " "${PACKAGE_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_BOARD_REMOVE (super-final)) " "${PACKAGE_LIST_BOARD_REMOVE}" "info"
}

# almost the last thing before copying to SD.
# this is called by post_debootstrap_tweaks() after ${SDCARD} is chroot_unmounted
# -> which is called by  debootstrap_ng() before prepare_partitions()/create_image()
# -> tmpfs is still going at this point.
config_post_debootstrap_tweaks__hack_armbianEnv_ci_args() {
	# This really is used for jumpstart and emmc, no way to actually discern yet.
	# shellcheck disable=SC2129
	echo "extraboardargs=${KERNEL_EXTRA_CMDLINE_SD}" >>"${SDCARD}"/boot/armbianEnv.txt

	# This is just there for the future
	echo "extraboardargssd=${KERNEL_EXTRA_CMDLINE_SD}" >>"${SDCARD}"/boot/armbianEnv.txt
	echo "extraboardargsemmc=${KERNEL_EXTRA_CMDLINE_EMMC}" >>"${SDCARD}"/boot/armbianEnv.txt
}

# almost the last thing before copying to SD.
# this is called by post_debootstrap_tweaks() after ${SDCARD} is chroot_unmounted
# -> which is called by  debootstrap_ng() before prepare_partitions()/create_image()
# -> tmpfs is still going at this point.
config_post_debootstrap_tweaks__make_sure_hostapd_behaves() {
	# hostapd REALLY should not be here @TODO: find out really what is installing it and remove this
	[[ -f "${SDCARD}"/etc/systemd/system/multi-user.target.wants/hostapd.service ]] &&
		rm -f "${SDCARD}"/etc/systemd/system/multi-user.target.wants/hostapd.service

	[[ -f "${SDCARD}"/lib/systemd/system/hostapd.service ]] &&
		rm -f "${SDCARD}"/lib/systemd/system/hostapd.service

	[[ -f "${SDCARD}"/etc/init.d/hostapd ]] &&
		rm -f "${SDCARD}"/etc/init.d/hostapd

	#echo "tree for ${SDCARD}/etc/systemd/ "
	#tree "${SDCARD}"/etc/systemd
	#echo "tree for ${SDCARD}/lib/systemd "
	#tree "${SDCARD}"/lib/systemd
}

# almost the last thing before copying to SD.
# this is called by post_debootstrap_tweaks() after ${SDCARD} is chroot_unmounted
# -> which is called by  debootstrap_ng() before prepare_partitions()/create_image()
# -> tmpfs is still going at this point.
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
