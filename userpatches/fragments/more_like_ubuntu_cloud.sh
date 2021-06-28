source "${SRC}/fragments/hack/hack-armbian-packages.sh" # Common hacks with package lists.

### Hooks
# Remove packages that dont belong in a cloud image.
# Wifi, Chrony, etc.
user_config__remove_uncloudlike_packages() {
	display_alert "Removing" "uncloudlike packages: wifi, chrony, etc."
	remove_packages_everywhere chrony unattended-upgrades wpasupplicant rng-tools networkd-dispatcher iw crda wireless-regdb hping3 selinux-policy-default dkms vnstat packagekit policykit-1
	export PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD} systemd-timesyncd" # chrony does not play well with systemd / qemu-agent.
}

# Tweak the BSP, removing a bunch of stuff that's great for interactive end-users and memory-deprived systems,
# but not so much for something is is provisioned like a cloud instance.
post_family_tweaks_bsp__be_more_like_ubuntu_cloud() {
	# remove a bunch of stuff from bsp so it behaves more like regular ubuntu
	rm -f "$destination"/etc/apt/apt.conf.d/02-armbian-compress-indexes

	rm -f "$destination"/etc/cron.d/armbian-truncate-logs
	rm -f "$destination"/etc/cron.d/armbian-updates
	rm -f "$destination"/etc/cron.daily/armbian-ram-logging

	rm -f "$destination"/etc/default/armbian-ramlog.dpkg-dist
	rm -f "$destination"/etc/default/armbian-zram-config.dpkg-dist

	rm -f "$destination"/etc/profile.d/armbian-check-first-login.sh

	rm -f "$destination"/etc/lib/systemd/system/systemd-journald.service.d/override.conf

	rm -f "$destination"/etc/lib/systemd/system/armbian-firstrun.service
	rm -f "$destination"/etc/lib/systemd/system/armbian-ramlog.service
	rm -f "$destination"/etc/lib/systemd/system/armbian-resize-filesystem.service
	rm -f "$destination"/etc/lib/systemd/system/armbian-zram-config.service

	rm -f "$destination"/lib/systemd/system/armbian-firstrun-config.service
	rm -f "$destination"/lib/systemd/system/armbian-firstrun.service
	rm -f "$destination"/lib/systemd/system/armbian-resize-filesystem.service
	rm -f "$destination"/lib/systemd/system/armbian-zram-config.service
	rm -f "$destination"/lib/systemd/system/armbian-disable-autologin.service
	rm -f "$destination"/lib/systemd/system/armbian-ramlog.service
}
