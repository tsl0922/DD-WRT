/*
 * wireless_ralink.c
 *
 * Copyright (C) 2005 - 2018 Sebastian Gottschall <s.gottschall@dd-wrt.com>
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
#ifdef HAVE_RT2880
#define VISUALSOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <linux/wireless.h>

#include <broadcom.h>
#include <wlutils.h>
#include <utils.h>
#include <bcmparams.h>
#include <bcmnvram.h>

#include "wireless_generic.c"

static const char *ieee80211_ntoa(const uint8_t mac[6])
{
	static char a[18];
	int i;

	i = snprintf(a, sizeof(a), "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
	return (i < 17 ? NULL : a);
}

typedef union _MACHTTRANSMIT_SETTING {
	struct {
		unsigned short MCS:6;
		unsigned short ldpc:1;
		unsigned short BW:2;
		unsigned short ShortGI:1;
		unsigned short STBC:1;
		unsigned short eTxBF:1;
		unsigned short iTxBF:1;
		unsigned short MODE:3;
	} field;
	unsigned short word;
} MACHTTRANSMIT_SETTING, *PMACHTTRANSMIT_SETTING;

typedef struct _RT_802_11_MAC_ENTRY {
	unsigned char	ApIdx;
	unsigned char	Addr[ETHER_ADDR_LEN];
	unsigned char	Aid;
	unsigned char	Psm;     // 0:PWR_ACTIVE, 1:PWR_SAVE
	unsigned char	MimoPs;  // 0:MMPS_STATIC, 1:MMPS_DYNAMIC, 3:MMPS_Enabled
	char		AvgRssi0;
	char		AvgRssi1;
	char		AvgRssi2;
	unsigned int	ConnectedTime;
	MACHTTRANSMIT_SETTING	TxRate;
	unsigned int	LastRxRate;
} RT_802_11_MAC_ENTRY, *PRT_802_11_MAC_ENTRY;

typedef struct _RT_802_11_MAC_TABLE {
	unsigned long Num;
	RT_802_11_MAC_ENTRY Entry[128];
} RT_802_11_MAC_TABLE, *PRT_802_11_MAC_TABLE;

#define MODE_CCK		0
#define MODE_OFDM		1
#define MODE_HTMIX		2
#define MODE_HTGREENFIELD	3
#define MODE_VHT		4
#define MODE_HE		5
#define MODE_HE_SU		8
#define MODE_HE_24G		7
#define MODE_HE_5G		6
#define MODE_HE_EXT_SU		9
#define MODE_HE_TRIG		10
#define MODE_HE_MU		11
#define MODE_UNKNOWN		255

#define BW_20			0
#define BW_40			1
#define BW_80			2
#define BW_160			3
#define BW_10			4
#define BW_5			5
#define BW_8080		6

// SHORTGI
#define GI_400      1		// only support in HT mode
#define GI_800      0

#define RT_OID_802_11_QUERY_LAST_RX_RATE            0x0613
#define	RT_OID_802_11_QUERY_LAST_TX_RATE			0x0632

#define RTPRIV_IOCTL_GET_MAC_TABLE		(SIOCIWFIRSTPRIV + 0x0F)
#define RTPRIV_IOCTL_GET_MAC_TABLE_STRUCT					(SIOCIWFIRSTPRIV + 0x1F)	// modified by Red@Ralink, 2009/09/30

static const int
MCSMappingRateTable[] =
{
	/* CCK */
	1, 2, 5, 11,

	/* OFDM */
	6, 9, 12, 18, 24, 36, 48, 54,

	/* 11n 20MHz, 800ns GI */
	6,  13, 19,  26,  39,  52,  58, 65,			/* 1ss , MCS 0-7 */
	13, 26, 39,  52,  78, 104, 117, 130,		/* 2ss , MCS 8-15 */
	19, 39, 58,  78, 117, 156, 175, 195,		/* 3ss , MCS 16-23 */
	26, 52, 78, 104, 156, 208, 234, 260,		/* 4ss , MCS 24-31 */

	/* 11n 40MHz, 800ns GI */
	13,  27,  40,  54,  81, 108, 121, 135,
	27,  54,  81, 108, 162, 216, 243, 270,
	40,  81, 121, 162, 243, 324, 364, 405,
	54, 108, 162, 216, 324, 432, 486, 540,

	/* 11n 20MHz, 400ns GI */
	7,  14, 21,  28,  43,  57,  65,  72,
	14, 28, 43,  57,  86, 115, 130, 144,
	21, 43, 65,  86, 130, 173, 195, 216,
	28, 57, 86, 115, 173, 231, 260, 288,

	/* 11n 40MHz, 400ns GI */
	15,  30,  45,  60,  90, 120, 135, 150,
	30,  60,  90, 120, 180, 240, 270, 300,
	45,  90, 135, 180, 270, 360, 405, 450,
	60, 120, 180, 240, 360, 480, 540, 600,

	/* 11ac 20 Mhz 800ns GI */
	6,  13, 19, 26,  39,  52,  58,  65,  78,  87,     /*1ss mcs 0~8*/
	13, 26, 39, 52,  78,  104, 117, 130, 156, 173,     /*2ss mcs 0~8*/
	19, 39, 58, 78,  117, 156, 175, 195, 234, 260,   /*3ss mcs 0~9*/
	26, 52, 78, 104, 156, 208, 234, 260, 312, 0,     /*4ss mcs 0~8*/

	/* 11ac 40 Mhz 800ns GI */
	13,	27,	40,	54,	 81,  108, 121, 135, 162, 180,   /*1ss mcs 0~9*/
	27,	54,	81,	108, 162, 216, 243, 270, 324, 360,   /*2ss mcs 0~9*/
	40,	81,	121, 162, 243, 324, 364, 405, 486, 540,  /*3ss mcs 0~9*/
	54,	108, 162, 216, 324, 432, 486, 540, 648, 720, /*4ss mcs 0~9*/

	/* 11ac 80 Mhz 800ns GI */
	29,	58,	87,	117, 175, 234, 263, 292, 351, 390,   /*1ss mcs 0~9*/
	58,	117, 175, 243, 351, 468, 526, 585, 702, 780, /*2ss mcs 0~9*/
	87,	175, 263, 351, 526, 702, 0,	877, 1053, 1170, /*3ss mcs 0~9*/
	117, 234, 351, 468, 702, 936, 1053, 1170, 1404, 1560, /*4ss mcs 0~9*/

	/* 11ac 160 Mhz 800ns GI */
	58,	117, 175, 234, 351, 468, 526, 585, 702, 780, /*1ss mcs 0~9*/
	117, 234, 351, 468, 702, 936, 1053, 1170, 1404, 1560, /*2ss mcs 0~9*/
	175, 351, 526, 702, 1053, 1404, 1579, 1755, 2160, 0, /*3ss mcs 0~8*/
	234, 468, 702, 936, 1404, 1872, 2106, 2340, 2808, 3120, /*4ss mcs 0~9*/

	/* 11ac 20 Mhz 400ns GI */
	7,	14,	21,	28,  43,  57,   65,	 72,  86,  96,    /*1ss mcs 0~8*/
	14,	28,	43,	57,	 86,  115,  130, 144, 173, 192,    /*2ss mcs 0~8*/
	21,	43,	65,	86,	 130, 173,  195, 216, 260, 288,  /*3ss mcs 0~9*/
	28,	57,	86,	115, 173, 231,  260, 288, 346, 0,    /*4ss mcs 0~8*/

	/* 11ac 40 Mhz 400ns GI */
	15,	30,	45,	60,	 90,  120,  135, 150, 180, 200,  /*1ss mcs 0~9*/
	30,	60,	90,	120, 180, 240,  270, 300, 360, 400,  /*2ss mcs 0~9*/
	45,	90,	135, 180, 270, 360,  405, 450, 540, 600, /*3ss mcs 0~9*/
	60,	120, 180, 240, 360, 480,  540, 600, 720, 800, /*4ss mcs 0~9*/

	/* 11ac 80 Mhz 400ns GI */
	32,	65,	97,	130, 195, 260,  292, 325, 390, 433,  /*1ss mcs 0~9*/
	65,	130, 195, 260, 390, 520,  585, 650, 780, 866, /*2ss mcs 0~9*/
	97,	195, 292, 390, 585, 780,  0, 975, 1170, 1300, /*3ss mcs 0~9*/
	130, 260, 390, 520, 780, 1040,	1170, 1300, 1560, 1733, /*4ss mcs 0~9*/

	/* 11ac 160 Mhz 400ns GI */
	65,	130, 195, 260, 390, 520,  585, 650, 780, 866, /*1ss mcs 0~9*/
	130, 260, 390, 520, 780, 1040,	1170, 1300, 1560, 1733, /*2ss mcs 0~9*/
	195, 390, 585, 780, 1170, 1560,	1755, 1950, 2340, 0, /*3ss mcs 0~8*/
	260, 520, 780, 1040, 1560, 2080, 2340, 2600, 3120, 3466, /*4ss mcs 0~9*/
};

#define MAX_NUM_HE_BANDWIDTHS 4
#define MAX_NUM_HE_SPATIAL_STREAMS 4
#define MAX_NUM_HE_MCS_ENTRIES 12

static const int he_mcs_phyrate_mapping_table[MAX_NUM_HE_BANDWIDTHS][MAX_NUM_HE_SPATIAL_STREAMS][MAX_NUM_HE_MCS_ENTRIES] = 
{
	{ /* 20 Mhz*/
		{  8, 17,  25,  34,  51,  68,  77,  86, 103, 114, 129, 143 },		/* 1 SS */
		{ 17, 34,  51,  68, 103, 137, 154, 172, 206, 229, 258, 286 },		/* 2 SS */
		{ 25, 51,  77, 103, 154, 206, 232, 258, 309, 344, 387, 430 },		/* 3 SS */
		{ 34, 68, 103, 137, 206, 275, 309, 344, 412, 458, 516, 573 }		/* 4 SS */
	},
	{ /* 40 Mhz*/
		{ 17,  34,  51,  68, 103, 137, 154, 172, 206, 229,  258, 286 },
		{ 34,  68, 103, 137, 206, 275, 309, 344, 412, 458,  516, 573 },
		{ 51, 103, 154, 206, 309, 412, 464, 516, 619, 688,  774, 860 },
		{ 68, 137, 206, 275, 412, 550, 619, 688, 825, 917, 1032, 1147 }
	},
	{ /* 80 Mhz*/
		{  36,  72, 108, 144, 216,  288,  324,  360,  432,  480,  540, 600 },
		{  72, 144, 216, 288, 432,  576,  648,  720,  864,  960, 1080, 1201 },
		{ 108, 216, 324, 432, 648,  864,  972, 1080, 1297, 1441, 1621, 1801 },
		{ 144, 288, 432, 576, 864, 1152, 1297, 1141, 1729, 1921, 2161, 2401 }
	},
	{ /* 160 Mhz*/
		{ 72,  144, 216,  288,  432,  576,  648,  720,  864,  960, 1080, 1201 },
		{ 144, 288, 432,  576,  864, 1152, 1297, 1441, 1729, 1921, 2161, 2401 },
		{ 216, 432, 648,  864, 1297, 1729, 1945, 2161, 2594, 2882, 3242, 3602 },
		{ 288, 576, 864, 1152, 1729, 2305, 2594, 2882, 3458, 3843, 4323, 4803 },
	}
};

char* GetBW(int BW)
{
	switch(BW)
	{
	case BW_10:
		return "10";
	case BW_20:
		return "20";
	case BW_40:
		return "40";
	case BW_80:
		return "80";
	case BW_160:
		return "160";
	default:
		return "N/A";
	}
}

char* GetPhyMode(int Mode)
{
	switch(Mode)
	{
	case MODE_CCK:
		return "CCK";
	case MODE_OFDM:
		return "OFDM";
	case MODE_HTMIX:
		return "HTMIX";
	case MODE_HTGREENFIELD:
		return "HT_GF";
	case MODE_VHT:
		return "VHT";
	case MODE_HE:
	case MODE_HE_SU:
	case MODE_HE_24G:
	case MODE_HE_5G:
	case MODE_HE_EXT_SU:
	case MODE_HE_TRIG:
	case MODE_HE_MU:
		return "HE";
	default:
		return "N/A";
	}
}

static int
getMCS(MACHTTRANSMIT_SETTING HTSetting)
{
	int mcs_1ss = (int)HTSetting.field.MCS;

	if (HTSetting.field.MODE >= MODE_VHT) {
		if (mcs_1ss > 9)
			mcs_1ss %= 16;
	}

	return mcs_1ss;
}

static int getLegacyOFDMMCSIndex(unsigned char MCS)
{
	int mcs_index = MCS;
	if (MCS == 0xb)
		mcs_index = 0;
	else if (MCS == 0xf)
		mcs_index = 1;
	else if (MCS == 0xa)
		mcs_index = 2;
	else if (MCS == 0xe)
		mcs_index = 3;
	else if (MCS == 0x9)
		mcs_index = 4;
	else if (MCS == 0xd)
		mcs_index = 5;
	else if (MCS == 0x8)
		mcs_index = 6;
	else if (MCS == 0xc)
		mcs_index = 7;

	return mcs_index;
}

static int
getRate(MACHTTRANSMIT_SETTING HTSetting)
{
	int rate_count = sizeof(MCSMappingRateTable)/sizeof(int);
	int rate_index = 0;
	int mcs_1ss = 0;
	int num_ss_vht = 0;
	int bw = 0;

	if (HTSetting.field.MODE >= MODE_HE) {
		mcs_1ss = (unsigned char)HTSetting.field.MCS & 0xf;
		num_ss_vht = ((unsigned char)HTSetting.field.MCS >> 4) + 1;
		bw = (unsigned char)HTSetting.field.BW;

		if (bw > MAX_NUM_HE_BANDWIDTHS)
			bw = MAX_NUM_HE_BANDWIDTHS - 1;

		if (mcs_1ss > MAX_NUM_HE_MCS_ENTRIES)
			mcs_1ss = MAX_NUM_HE_MCS_ENTRIES - 1;
		
		if (num_ss_vht > MAX_NUM_HE_SPATIAL_STREAMS)
			num_ss_vht = MAX_NUM_HE_SPATIAL_STREAMS;

		return he_mcs_phyrate_mapping_table[bw][num_ss_vht-1][mcs_1ss];
	}
	
	if (HTSetting.field.MODE >= MODE_VHT) {
		mcs_1ss = (unsigned char)HTSetting.field.MCS & 0xf;
		num_ss_vht = ((unsigned char)HTSetting.field.MCS >> 4) + 1;

		if (HTSetting.field.BW == BW_20)
			rate_index = 140 + ((unsigned char)HTSetting.field.ShortGI * 160) + ((num_ss_vht - 1) * 10) + mcs_1ss;
		else if (HTSetting.field.BW == BW_40)
			rate_index = 180 + ((unsigned char)HTSetting.field.ShortGI * 160) + ((num_ss_vht - 1) * 10) + mcs_1ss;
		else if (HTSetting.field.BW == BW_80)
			rate_index = 220 + ((unsigned char)HTSetting.field.ShortGI * 160) + ((num_ss_vht - 1) * 10) + mcs_1ss;
		else if (HTSetting.field.BW == BW_160)
			rate_index = 260 + ((unsigned char)HTSetting.field.ShortGI * 160) + ((num_ss_vht - 1) * 10) + mcs_1ss;
	}
	else if (HTSetting.field.MODE >= MODE_HTMIX)
		rate_index = 12 + ((unsigned char)HTSetting.field.BW * 32) + ((unsigned char)HTSetting.field.ShortGI * 64) + ((unsigned char)HTSetting.field.MCS);
	else if (HTSetting.field.MODE == MODE_OFDM)
		rate_index = getLegacyOFDMMCSIndex((unsigned char)(HTSetting.field.MCS)) + 4;
	else if (HTSetting.field.MODE == MODE_CCK)
		rate_index = (unsigned char)(HTSetting.field.MCS);

	if (rate_index < 0)
		rate_index = 0;

	if (rate_index >= rate_count)
		rate_index = rate_count-1;

	return (MCSMappingRateTable[rate_index]);
}

extern int OidQueryInformation(unsigned long OidQueryCode, int socket_id, char *DeviceName, void *ptr, unsigned long PtrLength);

static void DisplayLastTxRxRateFor11n(char *ifname, int s, int nID, int *fLastTxRxRate)
{
	unsigned long lHTSetting;
	MACHTTRANSMIT_SETTING HTSetting;
	OidQueryInformation(nID, s, ifname, &lHTSetting, sizeof(lHTSetting));
	bzero(&HTSetting, sizeof(HTSetting));
	memcpy(&HTSetting, &lHTSetting, sizeof(HTSetting));
	*fLastTxRxRate = getRate(HTSetting);
}

EJ_VISIBLE void ej_assoc_count(webs_t wp, int argc, char_t ** argv)
{
	assoc_count_prefix(wp, "wl");
}

int active_wireless_if(webs_t wp, int argc, char_t ** argv, char *ifname, int *cnt, int globalcnt, int turbo, int macmask)
{
	char *radev = getRADev(ifname);
	if (!ifexists(radev)) {
		printf("IOCTL_STA_INFO ifresolv %s failed!\n", ifname);
		return globalcnt;
	}
	int state = get_radiostate(ifname);
	if (state == 0 || state == -1) {
		return globalcnt;
	}
	int s = getsocket();
	if (s < 0) {
		return globalcnt;
	}

	int i, qual, rssi;
	RT_802_11_MAC_TABLE *mp;
	char mac_table_data[4096];
	struct iwreq wrq;
	int ignore = 0;

	int ap_idx = 0;
	if (!strcmp(radev, "ba0")) ap_idx = 1;

	bzero(mac_table_data, sizeof(mac_table_data));
	wrq.u.data.pointer = mac_table_data;
	wrq.u.data.length = sizeof(mac_table_data);
	wrq.u.data.flags = 0;
	strncpy(wrq.ifr_name, radev, IFNAMSIZ);

	if (ioctl(s, RTPRIV_IOCTL_GET_MAC_TABLE_STRUCT, &wrq) < 0) {
		ignore = 1;
	} else {
		mp = (RT_802_11_MAC_TABLE*)wrq.u.data.pointer;
	}

	if (!ignore && mp->Num < 128) {
		for (i = 0; i < mp->Num; i++) {
			if ((int)mp->Entry[i].ApIdx != ap_idx)
				continue;
			if (globalcnt)
				websWrite(wp, ",");
			*cnt = (*cnt) + 1;
			globalcnt++;
			char mac[32];
			strcpy(mac, ieee80211_ntoa(mp->Entry[i].Addr));
			if (nvram_matchi("maskmac", 1) && macmask) {
				mac[0] = 'x';
				mac[1] = 'x';
				mac[3] = 'x';
				mac[4] = 'x';
				mac[6] = 'x';
				mac[7] = 'x';
				mac[9] = 'x';
				mac[10] = 'x';
			}

			{
				int signal = (int)mp->Entry[i].AvgRssi0;
				if (signal > 0) signal = signal - 256;
				if (signal >= -50)
					qual = 1000;
				else if (signal <= -100)
					qual = 0;
				else
					qual = (signal + 100) * 20;

				char rx[32];
				char tx[32];
				int rate = getRate(mp->Entry[i].TxRate);
				snprintf(tx, 8, "%dM", rate);

				MACHTTRANSMIT_SETTING HTSetting;
				bzero(&HTSetting, sizeof(HTSetting));
				HTSetting.word = mp->Entry[i].LastRxRate;
				rate = getRate(HTSetting);
				snprintf(rx, 8, "%dM", rate);

				char mode[32];
				char *phy =GetPhyMode(mp->Entry[i].TxRate.field.MODE);
				char *bw = GetBW(mp->Entry[i].TxRate.field.BW);
				int mcs = getMCS(mp->Entry[i].TxRate);
				snprintf(mode, 32, "%s%s MCS%d", phy, bw, mcs);
				char info[32] = { 0 };
				if (mp->Entry[i].TxRate.field.ShortGI) strcat(info, "SGI ");
				if (mp->Entry[i].TxRate.field.ldpc) strcat(info, "LDPC ");
				if (mp->Entry[i].TxRate.field.STBC) strcat(info, "STBC");
				char str[64] = { 0 };

				websWrite(wp, "'%s','%s','%s','%s','%s','%s','%s','%d','%d','%d','%d','%d','%d','%d','0','%s','%s'",
					  mac, mode, radev, UPTIME(mp->Entry[i].ConnectedTime, str, sizeof(str)), tx, rx, info,
					  signal, -95, (mp->Entry[i].AvgRssi0 - (-95)), qual, mp->Entry[i].AvgRssi0,
					  mp->Entry[i].AvgRssi1, mp->Entry[i].AvgRssi2, nvram_nget("%s_label", radev),
					  radev);
			}
		}
	}
	STAINFO *sta = getRaStaInfo(ifname);

	if (sta) {
		char mac[32];
		if (globalcnt)
			websWrite(wp, ",");
		*cnt = (*cnt) + 1;
		globalcnt++;
		int signal = sta->rssi;
		if (signal >= -50)
			qual = 1000;
		else if (signal <= -100)
			qual = 0;
		else
			qual = (signal + 100) * 20;

		int rate = 1;
		char rx[32];
		char tx[32];
		DisplayLastTxRxRateFor11n(radev, s, RT_OID_802_11_QUERY_LAST_RX_RATE, &rate);
		snprintf(rx, 8, "%d.%d", rate / 1000, rate % 1000);
		DisplayLastTxRxRateFor11n(radev, s, RT_OID_802_11_QUERY_LAST_TX_RATE, &rate);
		snprintf(tx, 8, "%d.%d", rate / 1000, rate % 1000);

		strcpy(mac, ieee80211_ntoa(sta->mac));
		websWrite(wp, "'%s','N/A','%s','N/A','%s','%s','N/A','%d','%d','%d','%d','0','0','0','0'", mac, sta->ifname, tx, rx, sta->rssi, sta->noise, (sta->rssi - (sta->noise)), qual);
		debug_free(sta);

	}

	closesocket();
	return globalcnt;
}

EJ_VISIBLE void ej_active_wireless(webs_t wp, int argc, char_t ** argv)
{
	int i;
	char turbo[32];
	int t;
	int global = 0;
	int macmask = atoi(argv[0]);
	memset(assoc_count, 0, sizeof(assoc_count));
	t = 1;
	char *prefix = nvram_safe_get("wifi_display");
	if (!strcmp(prefix, "wl0"))
		global = active_wireless_if(wp, argc, argv, "wl0", &assoc_count[0], global, t, macmask);
	else if (!strcmp(prefix, "wl1"))
		global = active_wireless_if(wp, argc, argv, "wl1", &assoc_count[1], global, t, macmask);
}

extern long long wifi_getrate(char *ifname);

#define KILO	1000
#define MEGA	1000000
#define GIGA	1000000000

EJ_VISIBLE void ej_get_currate(webs_t wp, int argc, char_t ** argv)
{
	char mode[32];
	int state = get_radiostate(nvram_safe_get("wifi_display"));

	if (state == 0 || state == -1) {
		websWrite(wp, "%s", live_translate(wp, "share.disabled"));
		return;
	}
	long long rate = wifi_getrate(getRADev(nvram_safe_get("wifi_display")));
	char scale;
	long long divisor;

	if (rate >= MEGA) {
		scale = 'M';
		divisor = MEGA;
	} else {
		scale = 'k';
		divisor = KILO;
	}
	if (rate > 0.0) {
		websWrite(wp, "%lld %cbit/s", rate / divisor, scale);
	} else
		websWrite(wp, "%s", live_translate(wp, "share.auto"));

}

EJ_VISIBLE void ej_show_acktiming(webs_t wp, int argc, char_t ** argv)
{
	return;
}

EJ_VISIBLE void ej_update_acktiming(webs_t wp, int argc, char_t ** argv)
{
	return;
}

EJ_VISIBLE void ej_get_curchannel(webs_t wp, int argc, char_t ** argv)
{
	char *prefix = nvram_safe_get("wifi_display");
	int channel = wifi_getchannel(getRADev(prefix));

	if (channel > 0 && channel < 1000) {
		struct wifi_interface *interface = wifi_getfreq(getRADev(prefix));
		if (!interface) {
			websWrite(wp, "%s", live_translate(wp, "share.unknown"));
			return;
		}
		int freq = interface->freq;
		debug_free(interface);
		websWrite(wp, "%d", channel);
		if (has_mimo(prefix)
		    && (nvram_nmatch("n-only", "%s_net_mode", prefix)
			|| nvram_nmatch("mixed", "%s_net_mode", prefix)
			|| nvram_nmatch("na-only", "%s_net_mode", prefix)
			|| nvram_nmatch("n2-only", "%s_net_mode", prefix)
			|| nvram_nmatch("n5-only", "%s_net_mode", prefix)
			|| nvram_nmatch("ac-only", "%s_net_mode", prefix)
			|| nvram_nmatch("acn-mixed", "%s_net_mode", prefix)
			|| nvram_nmatch("ng-only", "%s_net_mode", prefix))
		    && (nvram_nmatch("ap", "%s_mode", prefix)
			|| nvram_nmatch("wdsap", "%s_mode", prefix)
			|| nvram_nmatch("infra", "%s_mode", prefix))) {

			if (nvram_nmatch("40", "%s_nbw", prefix)) {
				int ext_chan = 0;

				if (nvram_nmatch("lower", "%s_nctrlsb", prefix) || nvram_nmatch("ll", "%s_nctrlsb", prefix) || nvram_nmatch("lu", "%s_nctrlsb", prefix))
					ext_chan = 1;
				if (channel <= 4)
					ext_chan = 1;
				if (channel >= 10)
					ext_chan = 0;

				websWrite(wp, " + %d", !ext_chan ? channel - 4 : channel + 4);
			} else if (nvram_nmatch("80", "%s_nbw", prefix)) {
				if (nvram_nmatch("ll", "%s_nctrlsb", prefix) || nvram_nmatch("lower", "%s_nctrlsb", prefix))
					websWrite(wp, " + %d", channel + 6);
				if (nvram_nmatch("lu", "%s_nctrlsb", prefix))
					websWrite(wp, " + %d", channel + 2);
				if (nvram_nmatch("ul", "%s_nctrlsb", prefix))
					websWrite(wp, " + %d", channel - 2);
				if (nvram_nmatch("uu", "%s_nctrlsb", prefix) || nvram_nmatch("upper", "%s_nctrlsb", prefix))
					websWrite(wp, " + %d", channel - 6);
			}
		}
		websWrite(wp, " (%d MHz)", freq);

	} else
		websWrite(wp, "%s", live_translate(wp, "share.unknown"));
	return;
}

EJ_VISIBLE void ej_active_wds(webs_t wp, int argc, char_t ** argv)
{
}

#endif
