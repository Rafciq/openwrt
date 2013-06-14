#!/bin/sh
#
# sysinfo.sh dla OpenWRT AA Cezary Jackiewicz 2013
# 
#	1.00	CJ	Pierwsza wersja kodu
#	1.01	RD	Drobna przebudowa
#	1.02	RD	Korekta b³êdu wyœw. zajetoœci Flash-a, dodanie kolorów
#	1.03	RD	Dodanie nazwy routera, zmiana formatowania
#	1.04	RD	Kosmetyka, sugestie @mikhnal. Zmiana przetwarzania info. o wan.
#	1.05	RD	Zmiana algorytmu pobierania danych dla wan i lan
#	1.06	RD	Parametryzacja kolorów i pojawiania siê podkreœleñ
#	1.07	RD	Modyfikacja zwi¹zana z poprawnym wyœwietlaniem interfejsu dla prot.3g
#	1.08	RD	Modyfikacja wyœwietlania DNS-ów dla wan, dodanie uptime dla interfejsów
#	1.09	RD	Dodanie statusu "Down" dla wy³¹czonego wifi, zmiana wyœwietlania dla WLAN(sta)
#	1.10	RD	Korekta wyœwietlania dla WLAN(sta)
#	1.11	RD	Korekta wyœwietlania stanu pamiêci, sugestie @dopsz 
#	1.12	RD	Zmiana kolejnoœci wyœwietlania wartoœci stanu pamiêci + kosmetyka 
#	1.13	RD	Dodanie info o dhcp w LAN, zmiana sposobu wyœwietlania informacji o LAN
#	1.14	RD	Dodanie informacji o ostatnich b³êdach
#
# Destination /sbin/sysinfo.sh
#
. /usr/share/libubox/jshn.sh

local Width=60
local StartRuler="1"
local EndRuler="1"
local Rouler
local NormalColor=""
local MachineColor=""
local ValueColor=""
local AddrColor=""
local RXTXColor=""
local ErrorColor=""
local ExtraName=""
local ExtraValue=""

initialize() { # <Script Parameters>
	local ColorMode="c"
	while [ -n "$1" ]; do
		case "$1" in
		-m|--mono) ColorMode="m";;
		-bw|--black-white) ColorMode="bw";;
		-c2|--color-2) ColorMode="c2";;
		-sr|--no-start-ruler) StartRuler="0";;
		-er|--no-stop-ruler) EndRuler="0";;
		-w|--width) shift; Width=$1;;
		-en|--extra-name)	while [ -n "$2" ] && [ "${2:0:1}" != "-" ]; do
								shift
								[ "$ExtraName" != "" ] && ExtraName="$ExtraName "
								ExtraName="$ExtraName$1"
							done;;
		-ev|--extra-value)	while [ -n "$2" ] && [ "${2:0:1}" != "-" ]; do
								shift
								[ "$ExtraValue" != "" ] && ExtraValue="$ExtraValue "
								ExtraValue="$ExtraValue$1"
							done;;
		-h|--help)	echo -e	"Usage: $0 [option [option]]"\
							"\n\t-h\t\tThis help,"\
							"\n\t-m\t\tDisplay mono version,"\
							"\n\t-bw\t\tDisplay black-white version,"\
							"\n\t-c2\t\tDisplay alternative color version 2,"\
							"\n\t-sr\t\tWithout start horizontal ruler,"\
							"\n\t-er\t\tWithout end horizontal ruler,"\
							"\n\t-w N\t\tSet text display width to N characters (minimum 60)"\
							"\n\t-en Name\tExtra name"\
							"\n\t-ev Value\tExtra value"
					exit 1;;
		*) echo "Invalid option: $1";;
		esac
		shift;
	done
	case "$ColorMode" in
		c)	NormalColor="\e[0m"
			MachineColor="\e[0;33m"
			ValueColor="\e[1;36m"
			AddrColor="\e[1;31m"
			RXTXColor="\e[2;32m"
			ErrorColor="\e[0;31m";;
		c2)	NormalColor="\e[0m"
			MachineColor="\e[0;31m"
			ValueColor="\e[0;33m"
			AddrColor="\e[0;35m"
			RXTXColor="\e[0;36m"
			ErrorColor="\e[0;31m";;
		m)	NormalColor="\e[0m"
			MachineColor="\e[7m"
			ValueColor="\e[1m"
			AddrColor="\e[4m"
			RXTXColor="\e[1m"
			ErrorColor="\e[4";;
		*)	;;
	esac
	([ "$Width" == "" ] || [ "$Width" -lt 60 ]) && Width=60
	local i
	for i in $(seq $(expr $Width + 4 )); do 
		Rouler="$Rouler-";
	done
}

human_readable() { # <Number of bytes>
	if [ $1 -gt 0 ]; then
		printf "$(awk -v n=$1 'BEGIN{for(i=split("B KB MB GB TB PB",suffix);s<1;i--)s=n/(2**(10*i));printf (int(s)==s)?"%.0f%s":"%.1f%s",s,suffix[i+2]}')"
	else
		printf "0B"
	fi
}

device_rx_tx() { # <Device>
	local RXTX=$(awk -v Device=$1 '$1==Device ":"{printf "%.0f\t%.0f",$2,$10}' /proc/net/dev)
	[ "$RXTX" != "" ] && printf ", rx/tx: $RXTXColor$(human_readable $(echo "$RXTX" | cut -f 1))$NormalColor/$RXTXColor$(human_readable $(echo "$RXTX" | cut -f 2))$NormalColor"
}

uptime_str() { # <Time in Seconds>
	local Uptime=$1
	if [ $Uptime -gt 0 ]; then
		local Days=$(expr $Uptime / 60 / 60 / 24)
		local Hours=$(expr $Uptime / 60 / 60 % 24)
		local Minutes=$(expr $Uptime / 60 % 60)
		local Seconds=$(expr $Uptime % 60)
		if [ $Days -gt 0 ]; then
			Days=$(printf "%dd " $Days)
		else
			Days=""
		fi
		printf "$Days%02d:%02d:%02d" $Hours $Minutes $Seconds
	fi
}

print_line() { # <String to Print>, [[<String to Print>] ...]
	local Line="$@"
	printf " | %-${Width}s |\r | $Line\n"
}

print_horizontal_ruler() {
	printf " $Rouler\n"
}

print_machine() {
	local Machine=""
	local HostName=$(uci -q get system.@system[0].hostname)
	[ -e /tmp/sysinfo/model ] && Machine=$(cat /tmp/sysinfo/model)
	print_line 	"Machine: $MachineColor${Machine:-n/a}$NormalColor,"\
				"Name: $MachineColor${HostName:-n/a}$NormalColor"
}

print_times() {
	local SysUptime=$(cut -d. -f1 /proc/uptime)
	local Uptime=$(uptime_str $SysUptime)
	local Now=$(date +'%Y-%m-%d %H:%M:%S')
	print_line 	"System uptime: $ValueColor$Uptime$NormalColor,"\
				"Now: $ValueColor$Now$NormalColor"
}

print_loadavg() {
	local LoadAvg=$(awk '{printf"'$ValueColor'%s'$NormalColor', '$ValueColor'%s'$NormalColor', '$ValueColor'%s'$NormalColor'",$1,$2,$3}' /proc/loadavg)
	print_line "System load: $LoadAvg"
}

print_flash() {
	local Flash=$(df -k /overlay | awk '/overlay/{printf "%.0f\t%.0f\t%.1f\t%.0f",$2*1024,$3*1024,($2>0)?$3/$2*100:0,$4*1024}')
	local Total=$(echo "$Flash" | cut -f 1)
	local Used=$(echo "$Flash" | cut -f 2)
	local UsedPercent=$(echo "$Flash" | cut -f 3)
	local Free=$(echo "$Flash" | cut -f 4)
	print_line 	"Flash:"\
				"total: $ValueColor$(human_readable $Total)$NormalColor,"\
				"used: $ValueColor$(human_readable $Used)$NormalColor, $ValueColor$UsedPercent$NormalColor%%,"\
				"free: $ValueColor$(human_readable $Free)$NormalColor"
}

print_memory() {
	local Memory=$(awk 'BEGIN{Total=0;Free=0}$1~/^MemTotal:/{Total=$2}$1~/^MemFree:|^Buffers:|^Cached:/{Free+=$2}END{Used=Total-Free;printf"%.0f\t%.0f\t%.1f\t%.0f",Total*1024,Used*1024,(Total>0)?((Used/Total)*100):0,Free*1024}' /proc/meminfo)
	local Total=$(echo "$Memory" | cut -f 1)
	local Used=$(echo "$Memory" | cut -f 2)
	local UsedPercent=$(echo "$Memory" | cut -f 3)
	local Free=$(echo "$Memory" | cut -f 4)
	print_line "Memory:"\
				"total: $ValueColor$(human_readable $Total)$NormalColor,"\
				"used: $ValueColor$(human_readable $Used)$NormalColor, $ValueColor$UsedPercent$NormalColor%%,"\
				"free: $ValueColor$(human_readable $Free)$NormalColor"
}

print_wan() {
	local Zone
	local Device
	for Zone in $(uci -q show firewall | grep .masq= | cut -f2 -d.); do
		if [ "$(uci -q get firewall.$Zone.masq)" == "1" ]; then
			for Device in $(uci -q get firewall.$Zone.network); do
				local Status="$(ubus call network.interface.$Device status 2>/dev/null)"
				if [ "$Status" != "" ]; then
					local State=""
					local Iface=""
					local Uptime=""
					local IP4=""
					local IP6=""
					local Subnet4=""
					local Subnet6=""
					local Gateway4=""
					local Gateway6=""
					local DNS=""
					local Protocol=""
					json_load "${Status:-{}}"
					json_get_var State up
					json_get_var Uptime uptime
					json_get_var Iface l3_device
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
						[ "$IP4" != "" ] && print_line 	"WAN: $AddrColor$IP4$NormalColor($Iface),"\
														"gateway: $AddrColor${Gateway4:-n/a}$NormalColor"
						[ "$IP6" != "" ] && print_line	"WAN: $AddrColor$IP6$NormalColor($Iface),"\
														"gateway: $AddrColor${Gateway6:-n/a}$NormalColor"
						print_line	"proto: $ValueColor${Protocol:-n/a}$NormalColor,"\
									"uptime: $ValueColor$(uptime_str $Uptime)$NormalColor$(device_rx_tx $Iface)"
						[ "$DNS" != "" ] && print_line "dns: $AddrColor$DNS$NormalColor"
					fi
				fi
			done
		fi 
	done
}

print_lan() {
	local Zone
	local Device
	for Zone in $(uci -q show firewall | grep []]=zone | cut -f2 -d. | cut -f1 -d=); do
		if [ "$(uci -q get firewall.$Zone.masq)" != "1" ]; then
			for Device in $(uci -q get firewall.$Zone.network); do
				local Status="$(ubus call network.interface.$Device status 2>/dev/null)"
				if [ "$Status" != "" ]; then
					local State=""
					local Iface=""
					local IP4=""
					local IP6=""
					local Subnet4=""
					local Subnet6=""
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
					local DHCPConfig=$(uci -q show dhcp | grep .interface=$Device | cut -d. -f2)
					if [ "$DHCPConfig" != "" ] && [ "$(uci -q get dhcp.$DHCPConfig.ignore)" != "1" ]; then
						local DHCPStart=$(uci -q get dhcp.$DHCPConfig.start)
						local DHCPLimit=$(uci -q get dhcp.$DHCPConfig.limit)
						[ "$DHCPStart" != "" ] && [ "$DHCPLimit" != "" ] && DHCP="$(echo $IP4 | cut -d. -f1-3).$DHCPStart-$(expr $DHCPStart + $DHCPLimit - 1)"
					fi
					[ "$IP4" != "" ] && print_line "LAN: $AddrColor$IP4$NormalColor($Iface), dhcp: $AddrColor${DHCP:-n/a}$NormalColor"
					[ "$IP6" != "" ] && print_line "LAN: $AddrColor$IP6$NormalColor($Iface)"
				fi
			done
		fi 
	done
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
			local Connection="Down"
			if [ -n "$RadioIface" ]; then
				if [ "$Mode" == "ap" ]; then
					Connection="$(iw dev $RadioIface station dump | grep Station | wc -l)"
				else
					Connection="$(iw dev $RadioIface link | awk 'BEGIN{FS=": ";Signal="";Bitrate=""} $1~/signal/ {Signal=$2} $1~/tx bitrate/ {Bitrate=$2}END{print Signal" "Bitrate}')"
				fi
			fi
			if [ "$Mode" == "ap" ]; then
				print_line	"WLAN: $ValueColor$SSID$NormalColor($Mode),"\
							"ch: $ValueColor${Channel:-n/a}$NormalColor,"\
							"conn: $ValueColor$Connection$NormalColor$(device_rx_tx $RadioIface)"
			else
				print_line	"WLAN: $ValueColor$SSID$NormalColor($Mode),"\
							"ch: $ValueColor${Channel:-n/a}$NormalColor"
				print_line	"conn: $ValueColor$Connection$NormalColor$(device_rx_tx $RadioIface)"
			fi
		fi
	done
}

print_vpn() {
	local VPN
	for VPN in $(uci -q show openvpn | grep .ca= | cut -f2 -d.); do
		local Device=$(uci -q get openvpn.$VPN.dev)
		local Enabled=$(uci -q get openvpn.$VPN.enabled)
		if [ "$Enabled" == "1" ] || [ "$Enabled" == "" ]; then
			local Mode=$(uci -q get openvpn.$VPN.mode)
			local Connection="n/a"
			if [ "$Mode" == "server" ]; then
				Mode="$ValueColor$VPN$NormalColor(svr):$(uci -q get openvpn.$VPN.port)"
				Status=$(uci -q get openvpn.$VPN.status)
				Connection=$(awk 'BEGIN{FS=",";c=0;l=0}{if($1=="Common Name")l=1;else if($1=="ROUTING TABLE")exit;else if (l==1) c=c+1}END{print c}' $Status)
			else
				Mode="$ValueColor$VPN$NormalColor(cli)"
				Connection="Down"
				ifconfig $Device &>/dev/null && Connection="Up"
			fi
			print_line	"VPN: $Mode,"\
						"conn: $ValueColor$Connection$NormalColor$(device_rx_tx $Device)"
		fi
	done
}

print_extra() {
	([ "$ExtraName" != "" ] || [ "$ExtraValue" != "" ]) && print_line "$ExtraName $ValueColor$ExtraValue$NormalColor"
}

print_error() {
	logread | awk '/\w{3}+\.(err|warn|alert|emerg|crit)/{print " '$ErrorColor'"$0"'$NormalColor'"}'
}

initialize $@
[ "$StartRuler" == "1" ] && print_horizontal_ruler
print_machine
print_times
print_loadavg
print_flash
print_memory
print_wan
print_lan
print_wlan
print_vpn
print_extra
[ "$EndRuler" == "1" ] && print_horizontal_ruler
print_error
exit 0
# Done.
