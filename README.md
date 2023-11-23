# DD-WRT

dd-wrt build scripts and patches for MT7621, with ethernet/wireless drivers from [padavan](https://github.com/tsl0922/padavan) and Hardware NAT over `WAN<->LAN/WLAN`.

**Supported devices:**

- [PHICOMM K2P](https://openwrt.org/toh/phicomm/k2p_ke2p)
- [D-Link DIR-882 A1/R1](https://openwrt.org/toh/d-link/dir-882_a1)

## Prerequisites

Ubuntu-22.04

```bash
sudo apt install unzip libtool-bin ccache curl cmake gperf gawk flex bison nano xxd \
    fakeroot kmod cpio bc zip git python3-docutils gettext gengetopt gtk-doc-tools \
    autoconf-archive automake autopoint meson texinfo build-essential help2man pkg-config \
    zlib1g-dev libgmp3-dev libmpc-dev libmpfr-dev libncurses5-dev libltdl-dev wget libc-dev-bin
sudo apt install npm
sudo npm install -g uglify-js uglifycss
```

## Build Instructions

```
tar zxf toolchain-mipsel_24kc_gcc-13.1.0_musl.tar.gz
echo PROFILE=k2p > .config
make checkout
make prepare
make configure
make all
```

supported profiles are: `k2p k2p-mini k2p-mt76 dir-882-a1 dir-882-r1`.

`toolchain-mipsel_24kc_gcc-13.1.0_musl.tar.gz` can be downloaded from [release](https://github.com/tsl0922/DD-WRT/releases/tag/toolchain).
