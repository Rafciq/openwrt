#!/bin/sh
# WiFi Switcher - Access Point's sequential switch
# Script version 1.01 Rafal Drzymala 2012
#
# Changelog
#	1.00	RD	First stable code
#	1.01	RD	Fix state calculate bug. Minor cosmetic changes
#
# Destination /etc/hotplug.d/button/wifiswitcher
#
if [ "$BUTTON" == "BTN_1" ] && [ "$ACTION" == "released" ]; then
	SCR=$(basename $0)
	logger -p user.notice -t $SCR "Wifi button $BUTTON pressed"
	WLANS=$(uci show wireless | awk -F[.=] '{if ($3=="mode" && $4=="ap") print $2}')
	STATE=0
	MASK=1
	for WLAN in $WLANS; do
		OLD=$(uci -q get wireless.$WLAN.disabled)
		[ "$OLD" == "1" ] && STATE=$(($STATE + $MASK))
		MASK=$(($MASK << 1))
	done
	STATE=$(($STATE + 1))
	MASK=1
	for WLAN in $WLANS; do
		SSID=$(uci -q get wireless.$WLAN.ssid)
		OLD=$(uci -q get wireless.$WLAN.disabled)
		[ "$OLD" == "0" ] && OLD=""
		NEW="1"
		[ "$(($STATE & $MASK))" == "0" ] && NEW=""
		if ! [ "$OLD" == "$NEW" ]; then
			uci set wireless.$WLAN.disabled="$NEW"
			NEW=$([ "$NEW" == "1" ] && echo "off" || echo "on")
			logger -p user.notice -t $SCR "Wireless AP $SSID turn $NEW"
		fi
		MASK=$(($MASK << 1))
	done
	uci commit wireless
	wifi
fi
# Done 