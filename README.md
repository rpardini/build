### Armbian build system

- This (`rpardini/armbian-build`) fork is focused on some Amlogic/meson64 boards like the ODROID N2+, ODROID HC4, and an
  old chinese T95Z clone tvbox. A recent addition is the OnePlus 5 phone.
    - My notes on the [ODROID HC4](userpatches/hc4.README.md)
    - My notes on the [ODROID N2+](userpatches/n2plus.README.md)
    - My notes on the [OnePlus 5](userpatches/oneplus5.README.md) phone.
- It is used mainly to support a home Kubernetes cluster, running on mainline.
- Adds support for cloud-init, netplan, and generally behaves more like an Ubuntu Cloud instance or the Ubuntu
  RaspberryPi build.
- **Using the new Armbian build system extensibility hooks/fragments** which I'm trying to get upstreamed.
- Unsupported. Some (maybe...) useful backports to Armbian itself are cherry-picked from here and sent upstream.
- Experimental. Don't blame me, or anyone.

------------------------------------------------------------------------------------------------------------------------

[Go check out the upstream project](https://github.com/armbian/build)