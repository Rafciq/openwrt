#!/bin/sh
#
# sysinfo.sh dla OpenWRT AA Cezary Jackiewicz 2013
# 
#	1.00	CJ	Pierwsza wersja kodu
#	1.01	RD	Drobna przebudowa
#	1.02	RD	Korekta bledu wysw. zajetosci Flash-a, dodanie kolorow
#	1.03	RD	Dodanie nazwy routera, zmiana formatowania
#	1.04	RD	Kosmetyka, sugestie mikhnal. Zmiana przetwarzania info. o wan.
#	1.05	RD	Zmiana algorytmu pobierania danych dla wan i lan
#	1.06	RD	Parametryzacja kolorów i pojawiania siê podkreœleñ
#
# Destination /sbin/sysinfo.sh
#
. /usr/share/libubox/jshn.sh
#. /lib/functions/network.sh

local Width=60
local StartRuler="1"
local EndRuler="1"
local Rouler
local NormalColor
local MachineColor
local ValueColor
local AddrColor
local RXTXColor

initialize() {
	local ColorMode="1"
	for Parameter in $@; do
		case  $Parameter  in
		-m) ColorMode="0";;
		-sr) StartRuler="0";;
		-er) EndRuler="0";;
		-w)	Width=120;;
		-h|*)	
			echo "Usage: $0 - [parameter]"
			echo "	-h	: This help."
			echo "	-m	: Display mono version."
			echo "	-sr : Without start horizontal ruler."	
			echo "	-er : Without end horizontal ruler."	
			exit 1;;
		esac
	done
	if [ "$ColorMode" == "1" ]; then
		NormalColor="\e[0m"
		MachineColor="\e[0;33m"
		ValueColor="\e[1;36m"
		AddrColor="\e[1;31m"
		RXTXColor="\e[2;32m"
	else
		NormalColor="\e[0m"
		MachineColor="\e[7m"
		ValueColor="\e[1m"
		AddrColor="\e[4m"
		RXTXColor="\e[1m"
	fi
	local i
	for i in $(seq $(expr $Width + 4 )); do 
		Rouler="$Rouler-";
	done
}

human_readable() {
	if [ $1 -gt 0 ]; then
		printf "$(awk -v n=$1 'BEGIN{for(i=split("B KB MB GB TB PB",suffix);s<1;i--)s=n/(2**(10*i));printf (int(s)=s)?"%.0f%s":"%.1f%s",s,suffix[i+2]}')"
	else
		printf "0B"
	fi
}

device_rx_tx() {
	local RXTX=$(awk -v Device=$1 '$1==Device ":"{printf "%d\t%d",$2,$10}' /proc/net/dev)
	[ "$RXTX" != "" ] && printf "rx/tx: $RXTXColor$(human_readable $(echo "$RXTX" | cut -f 1))$NormalColor/$RXTXColor$(human_readable $(echo "$RXTX" | cut -f 2))$NormalColor"
}

print_line() {
	printf " | %-${Width}s |\r | $1\n"
}

print_horizontal_ruler() {
	printf " $Rouler\n"
}

print_machine() {
	local Machine=""
	local HostName=$(uci -q get system.@system[0].hostname)
	[ -e /tmp/sysinfo/model ] && Machine=$(cat /tmp/sysinfo/model)
	print_line "Machine: $MachineColor$Machine$NormalColor, Name: $MachineColor$HostName$NormalColor"
}

print_uptime() {
	local Uptime=$(cut -d. -f1 /proc/uptime)
	local Days=$(expr $Uptime / 60 / 60 / 24)
	local Hours=$(expr $Uptime / 60 / 60 % 24)
	local Minutes=$(expr $Uptime / 60 % 60)
	local Seconds=$(expr $Uptime % 60)
	print_line "Uptime: $ValueColor$(printf '%dd %02d:%02d:%02d' $Days $Hours $Minutes $Seconds)$NormalColor, Now: $ValueColor$(date +'%Y-%m-%d %H:%M:%S')$NormalColor"
}

print_loadavg() {
	local LoadAvg=$(awk '{printf"%s, %s, %s",$1,$2,$3}' /proc/loadavg)
	print_line "Load: $ValueColor$LoadAvg$NormalColor"
}

print_flash() {
	local Flash=$(df -k /overlay | awk '/overlay/{printf "%d\t%d\t%.1f",$4*1024,$2*1024,($2>0)?$3/$2*100:0}')
	local Free=$(echo "$Flash" | cut -f 1)
	local Total=$(echo "$Flash" | cut -f 2)
	local Used=$(echo "$Flash" | cut -f 3)
	print_line "Flash: free: $ValueColor$(human_readable $Free)$NormalColor, total: $ValueColor$(human_readable $Total)$NormalColor, used: $ValueColor$Used$NormalColor%%"
}

print_memory() {
	local Memory=$(awk 'BEGIN{Total=0;Free=0}$1~/^MemTotal:/{Total=$2}$1~/^MemFree:|^Buffers:|^Cached:/{Free+=$2}END{printf"%d\t%d\t%.1f",Free*1024,Total*1024,(Total>0)?(((Total-Free)/Total)*100):0}' /proc/meminfo)
	local Free=$(echo "$Memory" | cut -f 1)
	local Total=$(echo "$Memory" | cut -f 2)
	local Used=$(echo "$Memory" | cut -f 3)
	print_line "Memory: free: $ValueColor$(human_readable $Free)$NormalColor, total: $ValueColor$(human_readable $Total)$NormalColor, used: $ValueColor$Used$NormalColor%%"
}

print_wan() {
	local Zone
	local Device
	local State
	local Iface
	local IP4
	local IP6
	local Subnet4
	local Subnet6
	local Gateway4
	local Gateway6
	local DNS
	local Protocol
	for Zone in $(uci -q show firewall | grep .masq= | cut -f2 -d.); do
		for Device in $(uci -q get firewall.$Zone.network); do
			local Status="$(ubus call network.interface.$Device status 2>/dev/null)"
			if [ "$Status" != "" ]; then
				json_load "${Status:-{}}"
				json_get_var State up
				json_get_var Iface device
				json_get_var Protocol proto
				if json_get_type Status ipv4_address && [ "$Status" = array ]; then
					json_select ipv4_address
					json_get_type Status 1
					if [ "$Status" = object ]; then
						json_select 1
						json_get_var IP4 address
						json_get_var Subnet4 mask
						[ "$IP4" != "" ] && [ "$Subnet4" != "" ] && IP4="$IP4/$Subnet4"
					fi
				fi
				json_select
				if json_get_type Status ipv6_address && [ "$Status" = array ]; then
					json_select ipv6_address
					json_get_type Status 1
					if [ "$Status" = object ]; then
						json_select 1
						json_get_var IP6 address
						json_get_var Subnet6 mask
						[ "$IP6" != "" ] && [ "$Subnet6" != "" ] && IP6="$IP6/$Subnet6"
					fi
				fi
				json_select
				if json_get_type Status route && [ "$Status" = array ]; then
					json_select route
					local Index="1"
					while json_get_type Status $Index && [ "$Status" = object ]; do
						json_select "$((Index++))"
						json_get_var Status target
						case "$Status" in
							0.0.0.0)
								json_get_var Gateway4 nexthop;;
							::)
								json_get_var Gateway6 nexthop;;
						esac
						json_select ".."
					done	
				fi
				json_select
				if json_get_type Status dns_server && [ "$Status" = array ]; then
					json_select dns_server
					local Index="1"
					while json_get_type Status $Index && [ "$Status" = string ]; do
						json_get_var Status "$((Index++))"
						DNS="${DNS:+$DNS }$Status"
					done
				fi
				if [ "$State" == "1" ]; then
					[ "$IP4" != "" ] && print_line "WAN: $AddrColor$IP4$NormalColor($Iface), gateway: $AddrColor$Gateway4$NormalColor"
					[ "$IP6" != "" ] && print_line "WAN: $AddrColor$IP6$NormalColor($Iface), gateway: $AddrColor$Gateway6$NormalColor"
					print_line "proto: $ValueColor$Protocol$NormalColor, $(device_rx_tx $Iface)"
					print_line "dns: $AddrColor$DNS$NormalColor"
				fi
			fi
		done
	done
}

print_lan() {
	local Device="lan"
	local State
	local Iface
	local IP4
	local IP6
	local Subnet4
	local Subnet6
	local Status="$(ubus call network.interface.$Device status 2>/dev/null)"
	if [ "$Status" != "" ]; then
		json_load "${Status:-{}}"
		json_get_var State up
		json_get_var Iface device
		if json_get_type Status ipv4_address && [ "$Status" = array ]; then
			json_select ipv4_address
			json_get_type Status 1
			if [ "$Status" = object ]; then
				json_select 1
				json_get_var IP4 address
				json_get_var Subnet4 mask
				[ "$IP4" != "" ] && [ "$Subnet4" != "" ] && IP4="$IP4/$Subnet4"
			fi
		fi
		json_select
		if json_get_type Status ipv6_address && [ "$Status" = array ]; then
			json_select ipv6_address
			json_get_type Status 1
			if [ "$Status" = object ]; then
				json_select 1
				json_get_var IP6 address
				json_get_var Subnet6 mask
				[ "$IP6" != "" ] && [ "$Subnet6" != "" ] && IP6="$IP6/$Subnet6"
			fi
		fi
		[ "$IP4" != "" ] && print_line "LAN: $AddrColor$IP4$NormalColor"
		[ "$IP6" != "" ] && print_line "LAN: $AddrColor$IP6$NormalColor"
	fi
}

print_wlan() {
	local Iface
	for Iface in $(uci -q show wireless | grep device=radio | cut -f2 -d.); do
		local Device=$(uci -q get wireless.$Iface.device)
		local SSID=$(uci -q get wireless.$Iface.ssid)
		local IfaceDisabled=$(uci -q get wireless.$Iface.disabled)
		local DeviceDisabled=$(uci -q get wireless.$Device.disabled)
		if [ -n "$SSID" ] && [ "$IfaceDisabled" != "1" ] && [ "$DeviceDisabled" != "1" ]; then
			local Mode=$(uci -q -P /var/state get wireless.$Iface.mode)
			local Channel=$(uci -q get wireless.$Device.channel)
			local RadioIface=$(uci -q -P /var/state get wireless.$Iface.ifname)
			if [ -n "$RadioIface" ]; then
				if [ "$Mode" == "ap" ]; then
					Connection="$(iw dev $RadioIface station dump | grep Station | wc -l)"
				else
					Connection="$(iw dev $RadioIface link | awk 'BEGIN{FS=": ";Signal="";Bitrate=""} $1~/signal/ {Signal=$2} $1~/tx bitrate/ {Bitrate=$2}END{print Signal" "Bitrate}')"
				fi
			fi
			print_line "WLAN: $ValueColor$SSID$NormalColor($Mode), ch: $ValueColor$Channel$NormalColor, conn: $ValueColor$Connection$NormalColor, $(device_rx_tx $RadioIface)"
		fi
	done
}

print_vpn() {
	local VPN
	for VPN in $(uci -q show openvpn | grep .ca= | cut -f2 -d.); do
		local Device=$(uci -q get openvpn.$VPN.dev)
		local Enabled=$(uci -q get openvpn.$VPN.enabled)
		if [ "$Enabled" == "1" ] || [ "$Enabled" == "" ]; then
			Mode=$(uci -q get openvpn.$VPN.mode)
			if [ "$Mode" == "server" ]; then
				Mode="$ValueColor$VPN$NormalColor(svr):$(uci -q get openvpn.$VPN.port)"
				Status=$(uci -q get openvpn.$VPN.status)
				Connection=$(awk 'BEGIN{FS=",";c=0;l=0}{if($1=="Common Name")l=1;else if($1=="ROUTING TABLE")exit;else if (l==1) c=c+1}END{print c}' $Status)
			else
				Mode="$ValueColor$VPN$NormalColor(cli)"
				Connection="Down"
				ifconfig $Device &>/dev/null && Connection="Up"
			fi
			print_line "VPN: $Mode, conn: $ValueColor$Connection$NormalColor, $(device_rx_tx $Device)"
		fi
	done
}

initialize $@
[ "$StartRuler" == "1" ] && print_horizontal_ruler
print_machine
print_uptime
print_loadavg
print_flash
print_memory
print_wan
print_lan
print_wlan
print_vpn
[ "$EndRuler" == "1" ] && print_horizontal_ruler
exit 0
