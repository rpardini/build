# Hardkernel ODROID HC4

## Current status

- Using Armbian's meson64 default u-boot, `BOOTBRANCH="tag:v2021.04"` on HC4
- Some kernel patches allow for `fancontrol` and `pwmconfig` to work.
  - The little fan on the HC4 gets quite loud on full power, so I use `MAXPWM=hwmon2/pwm1=180`

### BRANCH=current (5.10)

- Known-good version `KERNELBRANCH='tag:v5.10.7'` used in Production in late 2020/early 2021 is rock-stable. That was with a different u-boot version though.
- Recent (5.10.24+) versions hang on reboot. At least.
- Through bisect I determined that `KERNELBRANCH='tag:v5.10.23'` is the last good one for the HC4.
  - N2+ also benefits from this, although it has other issues (USB especially)

### BRANCH=legacy (4.9)

- HC4 with legacy branch does not detect SATA disks, and there is a huge ammount of dmesg errors.


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
- Recent commits show SPI (NOR?) being added to DTB. Maybe one day we can write u-boot to it.

## And also

- There is red LED GPIO (HC4-only) in addition to the blue led GPIO in the C4
  - See patch for that in the DTB
- There is a GPIO (?) to control power to the SATA controller/disks?
    - How does this impact sleep/resume?
- I got the version with an OLED display and RTC.
    - I saw patches flying around for the OLED display? where?
- There is a reboot issue (DRAIN), fixed (?) in u-boot
