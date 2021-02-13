# Hardkernel ODROID HC4

## On paper

- "a C4 with SATA ports instead of USB3"
- comes with a case, _toaster_-style slots for HDDs or SSDs
    - case has a fan, controlled via pwm

## But also

- does NOT have eMMC socket (while the C4 does)
- has SPI NAND flash, 16mb ("Petitboot")
- CPU boots from SPI, unless the boot switch is pressed, in that case boots from SD
- if SPI is zeroed out (flash_eraseall in petitboot) always boots from SD card
- boot switch is under the board; location is very, very unfortunate; you have to remove SATA disks
- For now the only thing I can find that can write to SPI is a mysterious Petitboot-restore-flash SD card from HardKernel
- But of course, look at the spi docs at Hardkernels wiki, it's all there. overlays etc.
  - Worse that can happen is to break SPI boot, and against that there is the switch under the board
  - Not worth it for me. I'll be booting from SD and running a minimal root from there
    - `/etc/` and `/var` (and some swap) will be mounted on a fast SATA SSD
    - '/media' will be mounted on a slow SATA HDD

## And also

- There is red LED GPIO (HC4-only) in addition to the blue led GPIO in the C4
- There is a GPIO (?) to control power to the SATA controller/disks?
    - How does this impact sleep/resume?
- I got the version with an OLED display and RTC.
    - I saw patches flying around for the OLED display? where?
- There is a reboot issue (DRAIN), fixed (?) in u-boot

# Building

```bash
touch .ignore_changes

# mainline variant
sudo USE_GITHUB_UBOOT_MIRROR=yes ./compile.sh BOARD=odroidhc4 BRANCH=current KERNEL_ONLY=yes KERNEL_CONFIGURE=no

# tobetter variant
sudo USE_GITHUB_UBOOT_MIRROR=yes ./compile.sh BOARD=odroidhc4 BRANCH=current KERNEL_ONLY=yes KERNEL_CONFIGURE=no
```

# Patches

- patches at [ patch/kernel/meson64-current/board_odroidhc4 ]
- patches at [ patch/kernel/meson64-current/branch_current ]
- patches at [ patch/kernel/meson64-current/ ]

# SPI stuff?

- https://github.com/hardkernel/linux/blob/odroidg12-4.9.y-android/arch/arm64/boot/dts/amlogic/meson64_odroidhc4_android.dts

# Some more cmdlines

```bash
./compile.sh  BOARD=odroidhc4 BRANCH=current RELEASE=groovy BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=no COMPRESS_OUTPUTIMAGE=sha,img USE_GITHUB_UBOOT_MIRROR=no  INSTALL_HEADERS=no OFFLINE_WORK=yes BUILD_KSRC=no
```

### TOBETTER FULL

```bash
cd ~/IdeaProjects/armbian-tobetter && \
./compile.sh  BOARD=odroidhc4 BRANCH=tobetter RELEASE=groovy BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_ONLY=no KERNEL_CONFIGURE=yes COMPRESS_OUTPUTIMAGE=xz,sha,img USE_GITHUB_UBOOT_MIRROR=no  INSTALL_HEADERS=no BUILD_KSRC=no
```

# tobetter vs mainline
- https://github.com/torvalds/linux/compare/v5.10...tobetter:odroid-5.10.y
    - thanks github, that's unhelpful

