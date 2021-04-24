# Hardkernel ODROID N2+

## Current status

- Using Armbian's n2plus overriden default u-boot, which is Hardkernel's 2015.

### BRANCH=current (5.10)

- Version `KERNELBRANCH='tag:v5.10.7'` was used in production for a few months. Together with a JMicron USB3-SATA bridge. This is not stable, but can work for 24-48hs.
- Recent (5.10.24+) versions hang on reboot. At least.
- Through bisect I determined that `KERNELBRANCH='tag:v5.10.23'` is the last good one for the HC4.
  - N2+ also benefits from this, although it has other issues (USB especially)

### BRANCH=legacy (4.9)

- Usable. I just hate vendor kernels.

# USB3 woes

- This board N2/N2+ is specially susceptible to USB3 problems.
- I'm using the port furthest away from the DC jack.
- UAS/usb-storage makes little difference, it seems there is some underlying issue.

