#!/bin/sh
# DDNS update for DYNDNS.org
# Script version 1.00 Rafal Drzymala 2013
#
# Changelog
#	1.00	RD	First stable code
#
# Destination /etc/hotplug.d/iface/90-ddns-update
#

. /lib/functions.sh
. /lib/functions/network.sh

local wan_if

do_ddns() {
	local enabled
	local username
	local password
	local domain
	local wan_ip
	config_get_bool enabled $1 enabled 1
	if [ $enabled == 1 ] && [ "$1" == "$wan_if" ]; then
		config_get username $1 username
		config_get password $1 password
		config_get domain $1 domain
		network_get_ipaddr wan_ip $wan_if
		if [ "$wan_ip" == "" ]; then
			logger -p user.notice -t ddns-update "Unable to get interface $wan_if IP address."
			return
		fi
		logger -p user.notice -t ddns-update "Register in DDNS because interface $wan_if ($wan_ip) is up."
		local result=$(wget -q -O - "http://$username:$password@members.dyndns.org/nic/update?hostname=$domain&myip=$wan_ip")
		case $result in
			badauth)
				logger -p user.notice -t ddns-update "The username and password pair do not match a real user.";;
			good*)
				logger -p user.notice -t ddns-update "The update was successful, and the hostname is now updated.";;
			nochg*)
				logger -p user.notice -t ddns-update "The update changed no settings, and is considered abusive ($result).";;
			notfqdn)
				logger -p user.notice -t ddns-update "The hostname specified is not a fully-qualified domain name (not in the form hostname.dyndns.org or domain.com).";;
			nohost)
				logger -p user.notice -t ddns-update "The hostname specified does not exist in this user account (or is not in the service specified in the system parameter).";;
			numhost)
				logger -p user.notice -t ddns-update "Too many hosts (more than 20) specified in an update. Also returned if trying to update a round robin (which is not allowed).";;
			abuse)
				logger -p user.notice -t ddns-update "The hostname specified is blocked for update abuse.";;
			badagent)
				logger -p user.notice -t ddns-update "The user agent was not sent or HTTP method is not permitted (we recommend use of GET request method).";;
			dnserr)
				logger -p user.notice -t ddns-update "DNS error encountered.";;
			"911")
				logger -p user.notice -t ddns-update "There is a problem or scheduled maintenance on our side.";;
			*)
				logger -p user.notice -t ddns-update "Unknown result: $result";;
		esac
	fi
}

network_find_wan wan_if
[ "$wan_if" == "" ] && exit 0
if [ "$INTERFACE" == "$wan_if" ] && [ "$ACTION" == "ifup" ]; then
	config_load system
	config_foreach do_ddns ddns
fi
exit 0
# Done.