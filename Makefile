TOP_DIR:=$(CURDIR)

SVN := svn
SRC_DIR := $(TOP_DIR)/dd-wrt
SRC_URL := svn://svn.dd-wrt.com/DD-WRT
REVISION := HEAD

BUILD_DIR := $(SRC_DIR)/src/router
LINUX_DIR := $(SRC_DIR)/src/linux/universal/linux-4.14
TOOLCHAIN_DIR := $(TOP_DIR)/toolchain-mipsel_24kc_gcc-13.1.0_musl

define DefineProfile
  BOARD=$(1)
  DTS=$(2)
  CONFIG=$(3)
  KCONFIG=$(4)
endef

ifneq ($(wildcard .config),)
  include .config
endif

ifeq ($(PROFILE),k2p-mt76)
  $(eval $(call DefineProfile,k2p,K2P-mt76,mt76.config,mt76.config))
else ifeq ($(PROFILE),k2p)
  $(eval $(call DefineProfile,k2p,K2P,.config,.config))
else ifeq ($(PROFILE),k2p-mini)
  $(eval $(call DefineProfile,k2p,K2P,mini.config,.config))
else ifeq ($(PROFILE),dir-882-r1)
  $(eval $(call DefineProfile,dir-882,DIR-882-R1,.config,.config))
else ifeq ($(PROFILE),dir-882-a1)
  $(eval $(call DefineProfile,dir-882,DIR-882-A1,.config,.config))
else
  $(error "Unknown PROFILE=$(PROFILE)")
endif

MAKE_ROUTER := $(MAKE) -C $(BUILD_DIR) -f Makefile.mt7621 BOARD=$(BOARD) DTS=$(DTS) RPROFILE=$(PROFILE)
PATH := $(TOOLCHAIN_DIR)/bin:$(TOP_DIR)/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
KERNEL := universal/linux-4.14
CRDA_URL := git://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git

export PATH SVN

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
	$(MAKE_ROUTER) kernel
	$(MAKE_ROUTER) all
	$(MAKE_ROUTER) install
	$(MAKE_ROUTER) image

	mkdir -p images && cp $(BUILD_DIR)/mipsel-uclibc/dd-wrt-v3.0-*.bin images

checkout:
	-[ -d "$(SRC_DIR)" ] && svn cleanup $(SRC_DIR)
	$(SVN) co $(SRC_URL) -r $(REVISION) $(SRC_DIR) --depth immediates --quiet
	@for d1 in $$($(SVN) ls $(SRC_DIR) | grep '/$$'); do \
		[ "$$d1" = "ar5315_microredboot/" -o "$$d1" = "redboot/" ] && continue; \
		echo "== Updating $$d1"; \
		$(SVN) up -r $(REVISION) $(SRC_DIR)/$$d1 --set-depth immediates --quiet; \
		for d2 in $$($(SVN) ls $(SRC_DIR)/$$d1 | grep '/$$'); do \
			echo "== Updating $$d1$$d2"; \
			if [ "$$d1$$d2" = "src/linux/" ]; then \
				$(SVN) up -r $(REVISION) $(SRC_DIR)/$$d1$$d2 --set-depth immediates --quiet; \
			else \
				$(SVN) up -r $(REVISION) $(SRC_DIR)/$$d1$$d2 --set-depth infinity --quiet; \
			fi; \
		done; \
	done

	$(SVN) up -r $(REVISION) $(SRC_DIR)/src/linux/$(KERNEL) --set-depth infinity --quiet

	cp $(TOP_DIR)/files/router/Makefile.mt7621 $(BUILD_DIR)/Makefile.mt7621
	cp $(TOP_DIR)/configs/$(BOARD)/$(subst mini,,$(CONFIG)) $(BUILD_DIR)/.config

prepare:
	$(call PatchDir,$(TOP_DIR)/patches)
	$(call PatchDir,$(TOP_DIR)/patches/$(BOARD))
ifneq (,$(findstring mt76,$(PROFILE)))
	$(call PatchDir,$(TOP_DIR)/patches/mt76)
	[ -d $(BUILD_DIR)/crda ] || git clone $(CRDA_URL) $(BUILD_DIR)/crda
	echo "#!/bin/sh\n\necho crda called" > $(BUILD_DIR)/crda/crda.sh
	chmod +x $(BUILD_DIR)/crda/crda.sh
	ln -sf mac80211 $(BUILD_DIR)/compat-wireless
else
	$(call PatchDir,$(TOP_DIR)/patches/drv)
	rm -rf $(LINUX_DIR)/drivers/net/ethernet/raeth
	rm -rf $(LINUX_DIR)/net/nat/foe_hook
	cp -r $(TOP_DIR)/files/linux/drivers $(LINUX_DIR)/
	cp -r $(TOP_DIR)/files/linux/include $(LINUX_DIR)/
	cp -r $(TOP_DIR)/files/linux/net $(LINUX_DIR)/
	cp -r $(TOP_DIR)/files/router/* $(BUILD_DIR)/
endif
	cp $(TOP_DIR)/configs/$(BOARD)/dts/$(DTS).dts $(LINUX_DIR)/dts/$(DTS).dts
	cp $(TOP_DIR)/configs/$(BOARD)/kernel/$(KCONFIG) $(LINUX_DIR)/.config
	cp $(TOP_DIR)/configs/$(BOARD)/$(CONFIG) $(BUILD_DIR)/.config
	ln -sf ../../opt $(BUILD_DIR)/opt
	cp $(LINUX_DIR)/drivers/net/wireless/Kconfig.dir882 $(LINUX_DIR)/drivers/net/wireless/Kconfig

	$(MAKE_ROUTER) gen_revision

configure:
	$(MAKE_ROUTER) ncurses-configure ncurses
	$(MAKE_ROUTER) zlib-configure zlib
	$(MAKE_ROUTER) libffi-configure libffi
	$(MAKE_ROUTER) libnl-configure libnl
	$(MAKE_ROUTER) libpcap-configure libpcap
	$(MAKE_ROUTER) libucontext-configure libucontext
	$(MAKE_ROUTER) openssl-configure openssl
	$(MAKE_ROUTER) libevent-configure libevent
	$(MAKE_ROUTER) curl-configure curl
	$(MAKE_ROUTER) gmp-configure gmp
	$(MAKE_ROUTER) wolfssl-configure wolfssl
	$(MAKE_ROUTER) pcre-configure pcre
	$(MAKE_ROUTER) nettle-configure nettle
	$(MAKE_ROUTER) configure

httpd:
	$(MAKE_ROUTER) libutils-clean libutils
	$(MAKE_ROUTER) rc-clean rc
	$(MAKE_ROUTER) services-clean services
	$(MAKE_ROUTER) language routerstyle
	$(MAKE_ROUTER) httpd-clean httpd

gen_patches:
	@(cd $(SRC_DIR); \
		svn diff src/router/services/sysinit/defaults.c \
				src/router/services/sysinit/sysinit.c > $(TOP_DIR)/patches/k2p/defaults.patch; \
		svn diff src/router/libutils/libutils/detect.c \
				src/router/libutils/libutils/gpio.c \
				src/router/libutils/libutils/ledconfig.c \
				src/router/rc/resetbutton.c > $(TOP_DIR)/patches/k2p/k2p.patch; \
		svn diff src/router/kromo/dd-wrt/Makefile > $(TOP_DIR)/patches/k2p/kromo.patch; \
		svn diff src/router/services/sysinit/devinit.c > $(TOP_DIR)/patches/devinit.patch; \
		svn diff src/router/glib20/libglib/gio/meson.build \
				src/router/glib20/libglib/meson.build  > $(TOP_DIR)/patches/glib20.patch; \
		svn diff src/router/httpd/visuals/menu.c \
				src/router/httpd/visuals/dd-wrt.c > $(TOP_DIR)/patches/httpd.patch; \
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
		svn diff src/router/mac80211/drivers/net/wireless/mediatek/mt76 > $(TOP_DIR)/patches/mt76/mt76.patch; \
		svn diff src/linux/universal/linux-4.14/drivers/net/wireless/Kconfig.dir882 \
				src/linux/universal/linux-4.14/drivers/net/wireless/Makefile > $(TOP_DIR)/patches/drv/mt7615.patch; \
		svn diff src/router/others/Makefile > $(TOP_DIR)/patches/drv/others.patch; \
		svn diff src/router/rc/rc.c src/router/rc/Makefile > $(TOP_DIR)/patches/drv/mtk_esw.patch; \
		svn diff src/linux/universal/linux-4.14/net/wireless/wext-core.c > $(TOP_DIR)/patches/drv/wext-core.patch; \
		svn diff src/linux/universal/linux-4.14/dts/mt7621.dtsi \
				src/linux/universal/linux-4.14/net/Kconfig \
				src/linux/universal/linux-4.14/net/Makefile \
				src/linux/universal/linux-4.14/drivers/net/ethernet/Kconfig > $(TOP_DIR)/patches/drv/hw_nat.patch; \
		svn diff src/linux/universal/linux-4.14/net/ipv4/Kconfig \
				src/linux/universal/linux-4.14/net/ipv4/Makefile > $(TOP_DIR)/patches/drv/inet_lro.patch; \
		svn diff src/linux/universal/linux-4.14/include/linux/serial_core.h > $(TOP_DIR)/patches/serial.patch; \
		svn diff src/router/libutils/libwireless/wl.c > $(TOP_DIR)/patches/drv/libwireless.patch; \
		svn diff src/router/services/Makefile > $(TOP_DIR)/patches/drv/services.patch; \
	)

%:
	$(MAKE_ROUTER) $*