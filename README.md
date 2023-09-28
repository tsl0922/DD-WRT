# DD-WRT

dd-wrt build scripts and patches for PHICOMM K2P, with ethernet/wireless drivers from [padavan](https://github.com/tsl0922/padavan) and Hardware NAT over `WAN<->LAN/WLAN`.

## Prerequisites

Ubuntu-22.04

```bash
sudo apt install unzip libtool-bin ccache curl cmake gperf gawk flex bison nano xxd \
    fakeroot kmod cpio bc zip git python3-docutils gettext gengetopt gtk-doc-tools \
    automake autopoint meson texinfo build-essential help2man pkg-config zlib1g-dev \
    libgmp3-dev libmpc-dev libmpfr-dev libncurses5-dev libltdl-dev wget libc-dev-bin
sudo apt install npm
sudo npm install -g uglify-js uglifycss
```

## Build Instructions

1. extract [toolchain](https://github.com/tsl0922/DD-WRT/releases/tag/toolchain): `tar zxf toolchain-mipsel_24kc_gcc-13.1.0_musl.tar.gz`
2. checkout code: `make checkout`
3. prepare:
    - to use [mt_wifi](https://github.com/tsl0922/padavan/tree/main/trunk/linux-4.4.x/drivers/net/wireless/mediatek) driver: `make prepare DRV=mt_wifi`
    - to use [mt76](https://github.com/openwrt/mt76) driver: `make prepare DRV=mt76`
3. build:
    - `make configure`
    - `make kernel`
    - `make all`
    - `make image`

## References

- [PHICOMM K2P](https://openwrt.org/toh/phicomm/k2p_ke2p)
- [mt7621_phicomm_k2p.dts](https://github.com/openwrt/openwrt/blob/main/target/linux/ramips/dts/mt7621_phicomm_k2p.dts)
- [Mediatek Wi-Fi AP Software Programming Guide](https://mangopi.org/_media/mtk_wi-fi_softap_software_programming_guide_v4.6.pdf)