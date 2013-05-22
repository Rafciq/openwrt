#!/bin/sh
# Script for OpenVPN user/client authentication process
# Script version 1.00 Rafal Drzymala 2013
#
# Changelog
#	1.00	RD	First stable code
#
# Example usage in UCI version:
# server config pass credentials via file (is more secure)
#
#	option 'script_security' '2'
#	option 'auth_user_pass_verify' '/bin/openvpn-auth.sh via-file'
#
# or pass credentials via environment variables
#
#	option 'script_security' '3'
#	option 'auth_user_pass_verify' '/bin/openvpn-auth.sh via-env'
#
# Remember you have to add 'auth-user-pass' option in client config file.
#
if [ "$script_type" == "user-pass-verify" ]; then
	local LARG=""
	local PNAME=$(basename $0)
	for PARG in $(pgrep -s $PPID -fl)
	do 
		[ "$LARG" == "--syslog" ] && PNAME=$PARG && break
		LARG=$PARG
	done
	local PEER="$common_name $untrusted_ip:$untrusted_port"
	logger -p user.notice -t $PNAME "$PEER Start authentication"
	if [ "$1" == "" ]; then
		logger -p user.notice -t $PNAME "$PEER Authentication using variables"
	elif [ -e "$1" ]; then
		logger -p user.notice -t $PNAME "$PEER Authentication using file $1"
		local username=$(awk 'NR==1' $1)
		local password=$(awk 'NR==2' $1)
	else
		logger -p user.error -t $PNAME "$PEER Invalid parameters"
		exit 1
	fi
	if [ "$username" == "" ]; then
		logger -p user.error -t $PNAME "$PEER User name isn't set"
		exit 1
	fi
	if [ "$password" == "" ]; then
		logger -p user.error -t $PNAME "$PEER Password isn't set"
		exit 1
	fi
	local hashinput=$(echo "$password" | md5sum | cut -d " " -f 1)
	if [ "$hashinput" == "" ]; then
		logger -p user.error -t $PNAME "$PEER Hash from password isn't set"
		exit 1
	fi
	local hashuser=$(awk -v USER="$username" -F $'\t' '$1==USER {print $2}' /etc/openvpn/auth)
	if [ "$hashuser" == "" ]; then
		logger -p user.notice -t $PNAME "$PEER User '$username' not found"
		exit 1
	fi
	if [ "$hashuser" == "$hashinput" ]; then
		logger -p user.notice -t $PNAME "$PEER User $username authenticated"
		exit 0
	else
		logger -p user.notice -t $PNAME "$PEER Invalid password for user $username"
		exit 1
	fi
elif [ "$script_type" != "" ]; then
	logger -p user.error -t $PNAME "$PEER Invalid script type '$script_type'"
	exit 1
else
	exit 1
fi
# Done