#!/bin/sh
# DDNS update for DYNDNS.org, NO-IP.com, DDNS.pl, DNSDYNAMIC.org
# Script version 1.04 Rafal Drzymala 2013,2014
#
# Changelog
#	1.00	RD	First stable code
#	1.01	RD	Added detectip parameter
#	1.02	RD	Added service parameter
#	1.03	RD	Added ddns.pl, dnsdynamic.org
#	1.04	RD	Added optional parameter to run script manually.
#				Prevent for inactive DDNS record.
#				ex. /etc/hotplug.d/iface/90-ddns-update set 8.8.8.8
#
# Destination /etc/hotplug.d/iface/90-ddns-update
#

. /lib/functions.sh
. /lib/functions/network.sh

local wan_if

do_ddns() {
	local enabled
	local service
	local username
	local password
	local domain
	local detectip
	local wan_ip
	local service_url
	config_get_bool enabled $1 enabled 1
	if [ $enabled == 1 ]; then
		config_get service $1 service "dyndns.org"
		config_get username $1 username
		config_get password $1 password
		config_get domain $1 domain
		config_get_bool detectip $1 detectip 0
		case $service in
			dyndns.org)
				service_url="members.dyndns.org/nic/update";;
			no-ip.com)
				service_url="dynupdate.no-ip.com/nic/update";;
			ddns.pl)
				service_url="updates.ddns.pl/update_dyndns";;
			dnsdynamic.org)
				service_url="www.dnsdynamic.org/api/";;
			*)
				logger -p user.notice -t "ddns-update[$service]" "Unknown service: $service"
				return;;
		esac
		if [ -n "$2" ]; then
			wan_ip="set to $2"
			myip="&myip=$2"
		elif [ $detectip == 1 ]; then
			wan_ip="detect IP"
			myip=""
		else
			network_get_ipaddr wan_ip $wan_if
			if [ -z "$wan_ip" ]; then
				logger -p user.notice -t "ddns-update[$service]" "Unable to get interface $wan_if IP address."
				return
			fi
			myip="&myip=$wan_ip"
		fi
		logger -p user.notice -t "ddns-update[$service]" "Register in DDNS because interface $wan_if ($wan_ip) is up."
		local result=$(wget -q -O - "http://$username:$password@$service_url?hostname=$domain$myip")
		case $result in
			badauth)
				logger -p user.notice -t "ddns-update[$service]" "The username and password pair do not match a real user.";;
			good*)
				logger -p user.notice -t "ddns-update[$service]" "The update was successful, and the hostname is now updated.";;
			nochg*)
				logger -p user.notice -t "ddns-update[$service]" "The update changed no settings, and is considered abusive ($result).";;
			notfqdn)
				logger -p user.notice -t "ddns-update[$service]" "The hostname specified is not a fully-qualified domain name (not in the form hostname.dyndns.org or domain.com).";;
			nohost)
				logger -p user.notice -t "ddns-update[$service]" "The hostname specified does not exist in this user account (or is not in the service specified in the system parameter).";;
			numhost)
				logger -p user.notice -t "ddns-update[$service]" "Too many hosts (more than 20) specified in an update. Also returned if trying to update a round robin (which is not allowed).";;
			abuse)
				logger -p user.notice -t "ddns-update[$service]" "The hostname specified is blocked for update abuse.";;
			badagent)
				logger -p user.notice -t "ddns-update[$service]" "The user agent was not sent or HTTP method is not permitted (we recommend use of GET request method).";;
			dnserr)
				logger -p user.notice -t "ddns-update[$service]" "DNS error encountered.";;
			"911")
				logger -p user.notice -t "ddns-update[$service]" "There is a problem or scheduled maintenance on our side.";;
			*)
				logger -p user.notice -t "ddns-update[$service]" "Unknown result: $result";;
		esac
	fi
}

# Main rutine
local param_ip
[ "$1" == "set" ] && [ -n "$2" ] && param_ip="$2"
if [ "$ACTION" == "ifup" ] || [ -n "$1" ]; then
	network_find_wan wan_if
	if [[ -n "$wan_if"  && \( "$INTERFACE" == "$wan_if" ||  -n "$1" \) ]]; then
		config_load system
		config_foreach do_ddns ddns "$param_ip"
	fi
fi
#exit 0
# Done.
