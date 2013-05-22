#!/bin/sh
# Establishing 3G modem connection in dialup or NDIS mode
# Script version 1.10 Rafal Drzymala 2012,2013
#
# Changelog
#	1.00	RD	First stable code
#	1.01	RD	Prevent from parallel comgt/gcom execution
#	1.02	RD	Added logger priority, redirect comgt/gcom to logger
#	1.03	RD	Changed ICMP monitoring, use device, multiwan or default dns
#	1.04	RD	Changed ICMP data size to 1 byte
#	1.05	RD	Changed log messages, added wwan interface detection (frutis suggestion)
#	1.06	RD	Added router auto-reboot after connection timeout detected (if rebootafter option in network present)
#	1.07	RD	Added reboots log
#	1.08	RD	Improve reboot rutine
#	1.09	RD	Small improvements
#	1.10	RD	Changed FPATH to FILEPATH and TMPPATH
#
# Destination /bin/3gtester.sh
#
SCR=$(basename $0)
DEF_ICMP="8.8.8.8 8.8.4.4"
COMGT_APP="gcom"
NDISUP="/etc/gcom/ndisup.gcom"
FILEPATH="/usr/data"
TMPPATH="/tmp"
if ! which "$COMGT_APP" >/dev/null; then
	logger -p user.error -t $SCR "Application $COMGT_APP does not exist"
	exit
fi
[ -e "$NDISUP" ] ||	logger -p user.notice -t $SCR "Script $NDISUP does not exist"
[ -d "$FILEPATH" ] || mkdir -p $FILEPATH 
[ -d "$TMPPATH" ] || mkdir -p $TMPPATH 
WANS=$(uci show network | awk -F[.=] '{if (($3=="proto" && $4=="3g") || ($3=="ifname" && (match($4,"usb[0-9]") || match($4,"wwan[0-9]")))) print $2}')
for WAN in $WANS; do
	NDIS="N"
	UPTIME=$(cut -d "." -f1 /proc/uptime)
	NOW=$(date -u +"%Y.%m.%d-%H:%M:%S %s")
	[ $(uci -q get network.$WAN.proto) != "3g" ] && NDIS="Y"
	DEV_IFNAME=$(uci -q get network.$WAN.ifname)
	DEV_APN=$(uci -q get network.$WAN.apn)
	DEV_PINCODE=$(uci -q get network.$WAN.pincode)
	DEV_MODE=$(uci -q get network.$WAN.mode)
	DEV_REBOOTAFTER=$(uci -q get network.$WAN.rebootafter)
	[ "$NDIS" == "Y" ] && DEV_COMM=$(uci -q get network.$WAN.comm)
	[ "$NDIS" == "N" ] && DEV_COMM=$(uci -q get network.$WAN.device)
	DEV_AUTO="1"
	[ "$NDIS" == "N" ] && DEV_AUTO=$(uci -q get network.$WAN.auto)
	DEV_ICMP=$(uci -q get network.$WAN.dns)
	[ "$DEV_ICMP" == "" ] && DEV_ICMP=$(uci -q get multiwan.$WAN.dns)
	[ "$DEV_ICMP" == "" ] && DEV_ICMP=$DEF_ICMP
	logger -p user.notice -t $SCR "Checking for active connection $WAN ($DEV_IFNAME) attempting to ping $DEV_ICMP"
	if [ "$DEV_AUTO" == "1" ]; then
		if [ -e $DEV_COMM ]; then
			echo "$NOW $UPTIME" >$TMPPATH/$SCR.$WAN.check
			for ICMP in $DEV_ICMP; do
				if ping -q -c 1 -W 2 -s 1 -I $DEV_IFNAME $ICMP &>/dev/null; then
					ICMP_OK=$ICMP
					break
				fi
			done
			if [ "$ICMP_OK" != "" ]; then
				logger -p user.notice -t $SCR "ICMP successfully sent via $WAN ($DEV_IFNAME) to $ICMP_OK"
				echo "$NOW $UPTIME" >$TMPPATH/$SCR.$WAN.ok
			else
				logger -p user.notice -t $SCR "Restarting connection $WAN ($DEV_IFNAME) using device $DEV_COMM and apn $DEV_APN"
				[ "$DEV_MODE" != "" ] && logger -p user.notice -t $SCR "Using additional modem command $DEV_MODE"
				if [ "$NDIS" == "N" ]; then
					(ifdown $WAN; sleep 2; ifup $WAN) &
				else
					COMGT_DEV="-d $DEV_COMM"
					COMGT_SCR="-s $NDISUP"
					if pgrep -l -f "$COMGT_APP $COMGT_DEV $COMGT_SCR"> /dev/null; then
						logger -p user.notice -t $SCR "Connection $WAN ($DEV_IFNAME) is already restarted"
					elif pgrep -l -f "$COMGT_APP $COMGT_DEV"> /dev/null; then
						logger -p user.notice -t $SCR "Device $DEV_COMM used by another instance of $COMGT_APP"
					elif ([ "$DEV_COMM" == "/dev/ttyUSB2" ] || [ "$DEV_COMM" == "/dev/noz2" ] || [ "$DEV_COMM" == "/dev/modem" ]) && pgrep -l -f  "$COMGT_APP" | grep -q -v "\-d"> /dev/null; then
						logger -p user.notice -t $SCR "Device $DEV_COMM used by another instance of $COMGT_APP"
					else
						(ifdown $WAN; PINCODE=$DEV_PINCODE APN=$DEV_APN MODE=$DEV_MODE $COMGT_APP $COMGT_DEV $COMGT_SCR | logger -p user.notice -t $COMGT_APP; sleep 2; ifup $WAN) &
					fi
				fi
			fi
			if [ "$DEV_REBOOTAFTER" != "" ] && [ "$UPTIME" -ge "$DEV_REBOOTAFTER" ]; then
				LAST_ICMP_CHK=$(cut -d " " -f2 $TMPPATH/$SCR.$WAN.check)
				LAST_ICMP_OK=$(cut -d " " -f2 $TMPPATH/$SCR.$WAN.ok)
				if [ "$LAST_ICMP_CHK" != "" ] && [ "$LAST_ICMP_OK" != "" ] && [ "$LAST_ICMP_CHK" -ge "$LAST_ICMP_OK" ]; then
					SINCE_ICMP_OK=$(($LAST_ICMP_CHK-$LAST_ICMP_OK))
					[ "$SINCE_ICMP_OK" -gt "0" ] && logger -p user.notice -t $SCR "Lapsing $SINCE_ICMP_OK second(s) since the last sent the correct ICMP"
					if [ "$UPTIME" -ge "$DEV_REBOOTAFTER" ] && [ "$SINCE_ICMP_OK" -ge "$DEV_REBOOTAFTER" ]; then
						logger -p user.notice -t $SCR "Device $WAN ($DEV_IFNAME) reboot timeout detected, rebooting router..."
						echo "$NOW $UPTIME $WAN" >>$FILEPATH/$SCR.reboots
						reboot
					fi
				fi
			fi
		else
			logger -p user.error -t $SCR "Device $DEV_COMM for $WAN not exist"
		fi
	fi
done
# Done
