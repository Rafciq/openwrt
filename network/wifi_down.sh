#!/bin/sh
#
# Wireless conditional down
# 
#	1.00	RD	First stable code
#
# Destination /bin/wifi_down.sh
#
echo -n "Getting wireless infromation ..."
local Iface=""
local RadiosUp=0
local Connections=0
for Iface in $(uci -q show wireless | grep device=radio | cut -f2 -d.); do
	local Device=$(uci -q get wireless.$Iface.device)
	local IfaceDisabled=$(uci -q get wireless.$Iface.disabled)
	local DeviceDisabled=$(uci -q get wireless.$Device.disabled)
	if [ "$IfaceDisabled" != "1" ] && [ "$DeviceDisabled" != "1" ]; then
		local Mode=$(uci -q -P /var/state get wireless.$Iface.mode)
		local RadioUp=$(uci -q -P /var/state get wireless.$Iface.up)
		local RadioIface=$(uci -q -P /var/state get wireless.$Iface.ifname)
		[ "$RadioUp" == "1" ] && RadiosUp=$(expr $RadiosUp + 1)
		if [ -n "$RadioIface" ] && [ "$Mode" == "ap" ]; then
			Connections=$(expr $Connections + $(iw dev $RadioIface station dump 2>/dev/null| grep '^Station ' | wc -l))
		fi
	fi
done
echo -e "\nActive radio(s) $RadiosUp, Active connection(s) $Connections."
if [ $RadiosUp -gt 0 ] && [ $Connections -eq 0 ]; then
	echo "No wireless connection, shutting down the radio"
	wifi down
fi
# Done.