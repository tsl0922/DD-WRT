/*
 * sysinit-rt2880.c
 *
 * Copyright (C) 2008 Sebastian Gottschall <s.gottschall@dd-wrt.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 * $Id:
 */
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <syslog.h>
#include <signal.h>
#include <string.h>
#include <termios.h>
#include <sys/klog.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <linux/if_ether.h>
#include <linux/mii.h>
#include <linux/sockios.h>
#include <net/if.h>

#include <arpa/inet.h>
#include <sys/socket.h>
#include <linux/sockios.h>
#include <linux/mii.h>

#include <bcmnvram.h>
#include <shutils.h>
#include <utils.h>

#define sys_reboot() eval("sync"); eval("/bin/umount","-a","-r"); eval("event","3","1","15")

void start_sysinit(void)
{
	time_t tm = 0;

	mknod("/dev/mmc", S_IFBLK | 0660, makedev(126, 0));
	mknod("/dev/mmc0", S_IFBLK | 0660, makedev(126, 1));
	mknod("/dev/mmc1", S_IFBLK | 0660, makedev(126, 2));
	mknod("/dev/mmc2", S_IFBLK | 0660, makedev(126, 3));
	mknod("/dev/mmc3", S_IFBLK | 0660, makedev(126, 4));
	mknod("/dev/gpio", S_IFCHR | 0644, makedev(252, 0));

	/*
	 * Setup console 
	 */

	cprintf("sysinit() klogctl\n");
	klogctl(8, NULL, nvram_geti("console_loglevel"));
	cprintf("sysinit() get router\n");

	/*
	 * Set a sane date 
	 */
	stime(&tm);
	nvram_set("wl0_ifname", "ra0");

	insmod("thermal_sys");
	insmod("hwmon");

	eval("ifconfig", "eth2", "up");
	eval("ifconfig", "eth3", "up");

	eval("mtk_esw", "64", "0x401e", "0x10001");
	eval("mtk_esw", "64", "0x18001", "0x20002");

	eval("vconfig", "set_name_type", "VLAN_PLUS_VID_NO_PAD");
	eval("vconfig", "add", "eth2", "1");	//LAN
	eval("vconfig", "add", "eth3", "2");	//WAN

	insmod("hw_nat");

	char eabuf[32];
	if (get_hwaddr("eth2", eabuf)) {
		nvram_set("et0macaddr_safe", eabuf);
	}
}

int check_cfe_nv(void)
{
	nvram_seti("portprio_support", 0);
	return 0;
}

int check_pmon_nv(void)
{
	return 0;
}

void start_overclocking(void)
{
}

char *enable_dtag_vlan(int enable)
{
	return "eth2";
}

char *set_wan_state(int state)
{
	return NULL;
}

void start_devinit_arch(void)
{
}
