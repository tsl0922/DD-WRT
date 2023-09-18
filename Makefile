TOP_DIR:=$(CURDIR)

DRV = mt76
SVN = svn

SRC_DIR = $(TOP_DIR)/dd-wrt
BUILD_DIR = $(SRC_DIR)/src/router
LINUX_DIR = $(SRC_DIR)/src/linux/universal/linux-4.14
TOOLCHAIN_DIR = $(TOP_DIR)/toolchain-mipsel_24kc_gcc-13.1.0_musl

MAKE_ROUTER = $(MAKE) -C $(BUILD_DIR) -f Makefile.mt7621
PATH = $(TOOLCHAIN_DIR)/bin:$(TOP_DIR)/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CRDA_URL = git://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git
PKGS = coova-chilli curl ebtables-2.0.9 filesharing hostapd-2018-07-08 inadynv2 \
	kromo l7 libevent libffi libucontext libmicrohttpd libnl-tiny lzma-loader \
	$(if $(subst mt76,,$(DRV)),,mac80211 mac80211-rules) madwifi.dev \
	misc rp-pppoe rules tools udhcpc usb_modeswitch util-linux 

export PATH SVN

define CopyConfig
	cp $(TOP_DIR)/configs/$(if $(subst mt76,,$(1)),$(if $(subst mini,,$(1)),.config_drv,.config_mini),.config) $(BUILD_DIR)/.config
endef

define PatchDir
	@if [ -d $(1) ] && [ "$$(ls $(1) | wc -l)" -gt 0 ]; then \
		for p in $(1)/*.patch; do \
			echo "== Applying $$p..."; \
			for f in $$(grep '^Index: ' $$p | awk '{print $$2}'); do \
				svn revert $(SRC_DIR)/$$f; \
			done; \
			patch -t -d $(SRC_DIR) -p0 < $$p || true; \
		done \
	fi
endef

all:
	$(MAKE_ROUTER) all

checkout:
	-[ -d "$(SRC_DIR)" ] && svn cleanup $(SRC_DIR)
	$(SVN) co svn://svn.dd-wrt.com/DD-WRT $(SRC_DIR) --depth immediates --quiet
	@for d1 in $$($(SVN) ls $(SRC_DIR) | grep '/$$'); do \
		[ "$$d1" = "ar5315_microredboot/" -o "$$d1" = "redboot/" ] && continue; \
		echo "== Updating $$d1"; \
		$(SVN) up $(SRC_DIR)/$$d1 --set-depth immediates --quiet; \
		for d2 in $$($(SVN) ls $(SRC_DIR)/$$d1 | grep '/$$'); do \
			echo "== Updating $$d1$$d2"; \
			if [ "$$d1$$d2" = "src/linux/" -o "$$d1$$d2" = "src/router/" ]; then \
				$(SVN) up $(SRC_DIR)/$$d1$$d2 --set-depth immediates --quiet; \
			else \
				$(SVN) up $(SRC_DIR)/$$d1$$d2 --set-depth infinity --quiet; \
			fi; \
		done; \
	done

	@for dir in $(PKGS); do \
		echo "== Updating src/router/$$dir"; \
		$(SVN) up $(SRC_DIR)/src/router/$$dir --set-depth infinity --quiet; \
	done

	cp $(TOP_DIR)/files/router/Makefile.mt7621 $(BUILD_DIR)/Makefile.mt7621
	cp $(TOP_DIR)/configs/.config $(BUILD_DIR)/.config

	$(MAKE_ROUTER) download

gen_patches:
	@(cd $(SRC_DIR); \
		svn diff src/router/services/sysinit/defaults.c \
				src/router/services/sysinit/sysinit.c > $(TOP_DIR)/patches/defaults.patch; \
		svn diff src/router/glib20/libglib/gio/meson.build \
				src/router/glib20/libglib/meson.build  > $(TOP_DIR)/patches/glib20.patch; \
		svn diff src/router/httpd/visuals/menu.c > $(TOP_DIR)/patches/httpd.patch; \
		svn diff src/router/libutils/libutils/detect.c \
				src/router/libutils/libutils/gpio.c \
				src/router/libutils/libutils/ledconfig.c \
				src/router/rc/resetbutton.c > $(TOP_DIR)/patches/k2p.patch; \
		svn diff src/router/kromo/dd-wrt/Makefile > $(TOP_DIR)/patches/kromo.patch; \
		svn diff src/router/libpcap/gencode.c > $(TOP_DIR)/patches/libpcap.patch; \
		svn diff src/router/libutils/Makefile \
				src/router/libutils/libshutils/shutils.c > $(TOP_DIR)/patches/libutils.patch; \
		svn diff src/router/mactelnet/Makefile > $(TOP_DIR)/patches/mactelnet.patch; \
		svn diff src/router/ntfs3/Makefile > $(TOP_DIR)/patches/ntfs3.patch; \
		svn diff src/router/olsrd/src/cfgparser/local.mk > $(TOP_DIR)/patches/olsrd.patch; \
		svn diff src/router/rules > $(TOP_DIR)/patches/rules.patch; \
		svn diff src/router/shared > $(TOP_DIR)/patches/shared.patch; \
		svn diff src/router/vpnc/libgpg-error/src/Makefile.am \
				src/router/vpnc/libgpg-error/src/Makefile.in \
				src/router/vpnc/libgpg-error/src/mkstrtable.awk > $(TOP_DIR)/patches/vpnc.patch; \
		svn diff src/router/mac80211/drivers/net/wireless/Kconfig \
				src/router/mac80211/drivers/net/wireless/mediatek/mt76/Kconfig > $(TOP_DIR)/patches/mt76/mac80211.patch; \
		svn diff src/linux/universal/linux-4.14/drivers/net/wireless/Kconfig.dir882 \
				src/linux/universal/linux-4.14/drivers/net/wireless/Makefile > $(TOP_DIR)/patches/drv/mt7615.patch; \
		svn diff src/router/others/Makefile > $(TOP_DIR)/patches/drv/others.patch; \
		svn diff src/linux/universal/linux-4.14/net/wireless/wext-core.c > $(TOP_DIR)/patches/drv/wext-core.patch; \
		svn diff src/router/libutils/libwireless/wl.c > $(TOP_DIR)/patches/drv/libwireless.patch; \
	)

prepare:
	$(call PatchDir,$(TOP_DIR)/patches)
	$(call CopyConfig,$(DRV))
ifeq ($(DRV),mt76)
	$(call PatchDir,$(TOP_DIR)/patches/mt76)
	[ -d $(BUILD_DIR)/crda ] || git clone $(CRDA_URL) $(BUILD_DIR)/crda
	echo "#!/bin/sh\n\necho crda called" > $(BUILD_DIR)/crda/crda.sh
	chmod +x $(BUILD_DIR)/crda/crda.sh
	ln -sf mac80211 $(BUILD_DIR)/compat-wireless
	cp $(TOP_DIR)/files/linux/dts/K2P.dts $(LINUX_DIR)/dts/K2P.dts
	cp $(TOP_DIR)/configs/kernel/.config $(LINUX_DIR)/.config
else
	$(call PatchDir,$(TOP_DIR)/patches/drv)
	cp -r $(TOP_DIR)/files/linux/drivers $(LINUX_DIR)/
	cp -r $(TOP_DIR)/files/router/* $(BUILD_DIR)/
	cp $(TOP_DIR)/files/linux/dts/K2P_drv.dts $(LINUX_DIR)/dts/K2P.dts
	cp $(TOP_DIR)/configs/kernel/.config_drv $(LINUX_DIR)/.config
endif
	ln -sf ../../opt $(BUILD_DIR)/opt
	cp $(LINUX_DIR)/drivers/net/wireless/Kconfig.dir882 $(LINUX_DIR)/drivers/net/wireless/Kconfig

	$(MAKE_ROUTER) gen_revision

configure:
ifneq ($(DRV),mini)
	$(MAKE_ROUTER) ncurses-configure ncurses
	$(MAKE_ROUTER) zlib-configure zlib
	$(MAKE_ROUTER) libffi-configure libffi
	$(MAKE_ROUTER) libnl-configure libnl
	$(MAKE_ROUTER) libpcap-configure libpcap
	$(MAKE_ROUTER) libucontext-configure libucontext
	$(MAKE_ROUTER) openssl-configure openssl
	$(MAKE_ROUTER) curl-configure curl
	$(MAKE_ROUTER) gmp-configure gmp
	$(MAKE_ROUTER) wolfssl-configure wolfssl
endif
	$(MAKE_ROUTER) pcre-configure pcre
	$(MAKE_ROUTER) nettle-configure nettle
	$(MAKE_ROUTER) configure

image:
	$(MAKE_ROUTER) install
	$(MAKE_ROUTER) image
	mkdir -p images && cp $(BUILD_DIR)/mipsel-uclibc/dd-wrt-v3.0-*.bin images

httpd:
	$(MAKE_ROUTER) libutils-clean libutils
	$(MAKE_ROUTER) rc-clean rc
	$(MAKE_ROUTER) services-clean services
	$(MAKE_ROUTER) language routerstyle
	$(MAKE_ROUTER) httpd-clean httpd

%:
	$(MAKE_ROUTER) $*