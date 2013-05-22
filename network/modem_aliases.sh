#!/bin/sh
# Create alias for modem interface, based on its IMEI and sim ICCID
# Script version 1.00 Rafal Drzymala 2013
#
# Changelog
#	1.00	RD	First stable code
#
# Destination /etc/hotplug.d/usb/90-modem_aliases
#

do_modem_cmd() {
	local Device=$1
	local Cmd=$2
	printf "+++" >$Device 2>/dev/null
	sleep 1
	printf "\nATQ0V1E1\nAT$Cmd\n" >$Device 2>/dev/null
	awk '
	BEGIN {
		FS="\n";
		RS="\n";
		Step=1;
		Response=""}
	{	if ($1=="COMMAND NOT SUPPORT" || $1=="ERROR" || substr($1,1,11)=="+CME ERROR:")
			exit 1
		else if (Step==1 && $1=="OK")
			Step=2
		else if (Step==2 && $1=="AT'$Cmd'") 
			Step=3
		else if (Step==3 && $1!="" && $1!="OK")
			{ Step=4; Response=$1 }
		else if (Step==4 && $1=="OK") 
			exit}
	END {
		print Response}' $Device 2>/dev/null
}

get_modem_IMEI() {
	do_modem_cmd $1 "+CGSN"
}

get_sim_ICCID() {
	do_modem_cmd $1 "+CRSM=176,12258,0,0,10" | cut -d "," -f 3 | tr -d "\""
}

create_device_alias() {
	local DevicePath=$1
	local InterfaceAlias=$2
	if [ -L $InterfaceAlias ] && [ $(ls -l $InterfaceAlias | awk '{print $11}') != $DevicePath ]; then
		logger -p user.notice -t $SCR "$DEVICENAME Remove link $InterfaceAlias for device $DevicePath"
		rm -f $InterfaceAlias
	fi
	if [ ! -L $InterfaceAlias ]; then
		logger -p user.notice -t $SCR "$DEVICENAME Create link $InterfaceAlias for device $DevicePath"
		ln -sf $DevicePath $InterfaceAlias
	fi
}

cleanup_devices_aliases() {
	local DeviceInfo
	for DeviceInfo in $(ls -l /dev/*i? | awk '$9!="" && $11!="" {print $9":"$11}'); do
		local InterfaceAlias=$(echo "$DeviceInfo" | cut -d ":" -f 1)
		local DevicePath=$(echo "$DeviceInfo" | cut -d ":" -f 2)
		if [ ! -c $DevicePath ]; then
			logger -p user.notice -t $SCR "$DEVICENAME Remove link $InterfaceAlias for device $DevicePath"
			rm -f $InterfaceAlias
		fi
	done
}

if [ "$HOTPLUG_TYPE" == "usb" ] && [ "$DEVTYPE" == "usb_interface" ]; then
	case "$DEVICENAME" in
	*-*.*:*.*) : ;;
	*) exit 0 ;;
	esac
	SCR=$(basename $0)
	if [ "$ACTION" == "add" ]; then
		if [ -e /sys$DEVPATH/*/tty/*/dev ]; then
			local ModemIMEI
			local simICCID
			for InterfaceConfig in /sys$DEVPATH/../*/*/tty/*; do
				local InterfaceNumber=$(cut -d ':' -f 2 $InterfaceConfig/dev)
				if [ "$InterfaceNumber" != "" ]; then
					local ModemDevice=/dev/$(basename $InterfaceConfig)
					[ -c $ModemDevice ] && [ "$ModemIMEI" == "" ] && ModemIMEI=$(get_modem_IMEI $ModemDevice)
					if [ "$ModemIMEI" != "" ]; then
						local InterfaceAlias=/dev/"mdm"$ModemIMEI"i"$InterfaceNumber
						create_device_alias $ModemDevice $InterfaceAlias
					fi
					[ -c $ModemDevice ] && [ "$simICCID" == "" ] && simICCID=$(get_sim_ICCID $ModemDevice)
					if [ "$simICCID" != "" ]; then
						local InterfaceAlias=/dev/"sim"$simICCID"i"$InterfaceNumber
						create_device_alias $ModemDevice $InterfaceAlias
					fi
				fi
			done
		fi
	elif [ "$ACTION" == "remove" ]; then
		cleanup_devices_aliases
	fi
fi
#Done