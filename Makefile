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