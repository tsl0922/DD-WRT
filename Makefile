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
	kromo l7 libevent libffi libmicrohttpd libnl-tiny lzma-loader \
	$(if $(subst mt76,,$(DRV)),,mac80211 mac80211-rules) madwifi.dev \
	misc rp-pppoe rules tools udhcpc usb_modeswitch util-linux 

export PATH SVN

define PatchDir
	@for p in $(1)/*.patch; do \
		echo "== Applying $$p..."; \
		for f in $$(grep '^Index: ' $$p | awk '{print $$2}'); do \
			svn revert $(SRC_DIR)/$$f; \
		done; \
		patch -d $(SRC_DIR) -p0 < $$p; \
	done
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

	cp Makefile.mt7621 $(BUILD_DIR)/Makefile.mt7621
	cp configs/.config_k2p $(BUILD_DIR)/.config

	$(MAKE_ROUTER) download

prepare:
	$(call PatchDir,$(TOP_DIR)/patches)
ifeq ($(DRV),mt76)
	[ -d $(BUILD_DIR)/crda ] || git clone $(CRDA_URL) $(BUILD_DIR)/crda
	echo "#!/bin/sh\n\necho crda called" > $(BUILD_DIR)/crda/crda.sh
	chmod +x $(BUILD_DIR)/crda/crda.sh
	ln -sf mac80211 $(BUILD_DIR)/compat-wireless
	ln -sf $(TOP_DIR)/dts/K2P.dts $(LINUX_DIR)/dts/K2P.dts
	cp configs/.config_kernel $(LINUX_DIR)/.config
	cp configs/.config_k2p $(BUILD_DIR)/.config
else
	$(call PatchDir,$(TOP_DIR)/drivers/patches)
	rm -rf $(LINUX_DIR)/drivers/net/wireless/wifi_utility $(LINUX_DIR)/drivers/net/wireless/rt7615
	ln -sf $(TOP_DIR)/drivers/wifi_utility  $(LINUX_DIR)/drivers/net/wireless/wifi_utility
	ln -sf $(TOP_DIR)/drivers/mt7615 $(LINUX_DIR)/drivers/net/wireless/rt7615
	rm -rf $(BUILD_DIR)/others/rt2880/mt7615
	ln -sf $(TOP_DIR)/drivers/files $(BUILD_DIR)/others/rt2880/mt7615
	ln -sf $(TOP_DIR)/drivers/wireless_ralink.c $(BUILD_DIR)/httpd/visuals/wireless_ralink.c
	ln -sf $(TOP_DIR)/drivers/rt2880.c $(BUILD_DIR)/services/networking/wifi/rt2880.c
	ln -sf $(TOP_DIR)/dts/K2P_drv.dts $(LINUX_DIR)/dts/K2P.dts
	cp configs/.config_kernel_drv $(LINUX_DIR)/.config
	cp configs/.config_k2p_drv $(BUILD_DIR)/.config
endif
	ln -sf ../../opt $(BUILD_DIR)/opt
	cp $(LINUX_DIR)/drivers/net/wireless/Kconfig.dir882 $(LINUX_DIR)/drivers/net/wireless/Kconfig

	cp Makefile.mt7621 $(BUILD_DIR)/Makefile.mt7621
	$(MAKE_ROUTER) gen_revision

configure:
	(cd $(BUILD_DIR)/libevent; autoreconf -fi)
	(cd $(BUILD_DIR)/pcre; autoreconf -fi)
	$(MAKE_ROUTER) ncurses-configure ncurses
	$(MAKE_ROUTER) zlib-configure zlib
	$(MAKE_ROUTER) libffi-configure libffi
	$(MAKE_ROUTER) libnl-configure libnl
	$(MAKE_ROUTER) libpcap-configure libpcap
	$(MAKE_ROUTER) openssl-configure openssl
	$(MAKE_ROUTER) curl-configure curl
	$(MAKE_ROUTER) gmp-configure gmp
	$(MAKE_ROUTER) pcre-configure pcre
	$(MAKE_ROUTER) nettle-configure nettle
	$(MAKE_ROUTER) wolfssl-configure wolfssl
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