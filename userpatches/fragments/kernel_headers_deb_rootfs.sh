## Configuration
export COPY_HEADERS_DEB=yes # do copy the headers .deb to rootfs for easy later install?

# Copies a build linux-headers .deb inside the rootfs at /usr/src/
# Much faster than installing it on rootfs.
config_post_install_kernel_debs__copy_headers_deb_to_rootfs() {
	[[ -f "${DEB_STORAGE}/${CHOSEN_KERNEL/image/headers}_${REVISION}_${ARCH}.deb" ]] &&
		[[ "${COPY_HEADERS_DEB}" == "yes" ]] && cp "${DEB_STORAGE}/${CHOSEN_KERNEL/image/headers}_${REVISION}_${ARCH}.deb" "${SDCARD}"/usr/src/
}
