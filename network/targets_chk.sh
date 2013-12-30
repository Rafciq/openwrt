#!/bin/sh
# Checking host reachability
# Script version 1.03 Rafal Drzymala 2013
#
# Changelog
#	1.00	RD	First stable code
#	1.01	RD	Chaneg FPATH to FILEPATH and TMPPATH
#	1.02	RD	Add CMD_OK parameter. Change CMD to CMD_FAIL
#	1.03	RD	Change, run the command only once, per state change
#
# Destination /bin/targets_chk.sh
#
# Example execute by cron for every minute
#	* * * * * /bin/targets_chk.sh
#
#
SCR=$(basename $0)
FILEPATH="/usr/data"
TMPPATH="/tmp"
[ -d "$FILEPATH" ] || mkdir -p $FILEPATH 
[ -d "$TMPPATH" ] || mkdir -p $TMPPATH 
TARGETS=$(uci show network | awk -F[.=\] '{if (($3=="target")) print $2}')
for TARGET in $TARGETS; do
	UPTIME=$(cut -d "." -f1 /proc/uptime)
	NOW=$(date -u +"%Y.%m.%d-%H:%M:%S %s")
	TARGET_HOST=$(uci -q get network.$TARGET.host)
	TARGET_IFNAME=$(uci -q get network.$TARGET.ifname)
	TARGET_INTERVAL=$(uci -q get network.$TARGET.interval)
	TARGET_TIMEOUT=$(uci -q get network.$TARGET.timeout)
	TARGET_CMD_OK=$(uci -q get network.$TARGET.cmdok)
	TARGET_CMD_FAIL=$(uci -q get network.$TARGET.cmdfail)
	TARGET_WAIT=$(uci -q get network.$TARGET.wait)
	[ "$TARGET_WAIT" == "" ] && TARGET_WAIT="10"
	if [ "$TARGET_HOST" != "" ] && [ "$TARGET_IFNAME" != "" ] && [ "$TARGET_TIMEOUT" != "" ] && [ "$TARGET_CMD_OK$TARGET_CMD_FAIL" != "" ]; then
		LAST_CMD=$(cut -d " " -f2 $TMPPATH/$SCR.$TARGET.lastcmd) &>/dev/null
		LAST_ICMP_CHK=$(cut -d " " -f2 $TMPPATH/$SCR.$TARGET.check) &>/dev/null
		SINCE_ICMP_CHK="0"
		[ "$LAST_ICMP_CHK" != "" ] && SINCE_ICMP_CHK=$(($(echo "$NOW" | cut -d " " -f2)-$LAST_ICMP_CHK))
		if [ "$LAST_ICMP_CHK" == "" ] || [ "$TARGET_INTERVAL" == "" ] || [ "$SINCE_ICMP_CHK" -ge "$TARGET_INTERVAL" ]; then
			logger -p user.notice -t $SCR "Checking for connection to $TARGET_HOST with config $TARGET"
			echo "$NOW $UPTIME" >$TMPPATH/$SCR.$TARGET.check
			ICMP_OK=""
			for ICMP in $TARGET_HOST; do
				if ping -q -c 1 -W $TARGET_WAIT -s 1 -I $TARGET_IFNAME $ICMP &>/dev/null; then
					ICMP_OK=$ICMP
					break
				fi
			done
			if [ "$ICMP_OK" != "" ]; then
				logger -p user.notice -t $SCR "ICMP successfully sent via $TARGET_IFNAME to $ICMP_OK"
				echo "$NOW $UPTIME" >$TMPPATH/$SCR.$TARGET.ok
				if [ "$TARGET_CMD_OK" != "" ] && [ "$LAST_CMD" != "ok" ]; then
					logger -p user.notice -t $SCR "Executing $TARGET_CMD_OK"
					echo "ok" >$TMPPATH/$SCR.$TARGET.lastcmd
					echo "$NOW $UPTIME $TARGET $TARGET_CMD_OK" >>$FILEPATH/$SCR.execs
					eval "$TARGET_CMD_OK"
				fi
			else
				logger -p user.notice -t $SCR "Host $TARGET_HOST is unreachable via $TARGET_IFNAME"
			fi
			if [ "$UPTIME" -ge "$TARGET_TIMEOUT" ]; then
				LAST_ICMP_CHK=$(cut -d " " -f2 $TMPPATH/$SCR.$TARGET.check) &>/dev/null
				LAST_ICMP_OK=$(cut -d " " -f2 $TMPPATH/$SCR.$TARGET.ok) &>/dev/null
				if [ "$LAST_ICMP_OK"=="" ] || [ "$LAST_ICMP_CHK" -ge "$LAST_ICMP_OK" ]; then
					SINCE_ICMP_OK=""
					[ "$LAST_ICMP_OK" != "" ] && SINCE_ICMP_OK=$(($LAST_ICMP_CHK-$LAST_ICMP_OK))
					[ "$SINCE_ICMP_OK" -gt "0" ] && logger -p user.notice -t $SCR "Lapsing $SINCE_ICMP_OK second(s) since the last sent the correct ICMP, using config $TARGET"
					if [ "$SINCE_ICMP_OK" == "" ] || [ "$SINCE_ICMP_OK" -ge "$TARGET_TIMEOUT" ]; then
						logger -p user.notice -t $SCR "Timeout detected using config $TARGET via $TARGET_IFNAME"
						if [ "$TARGET_CMD_FAIL" != "" ] && [ "$LAST_CMD" != "fail" ]; then
							logger -p user.notice -t $SCR "Executing $TARGET_CMD_FAIL"
							echo "fail" >$TMPPATH/$SCR.$TARGET.lastcmd
							echo "$NOW $UPTIME $TARGET $TARGET_CMD_FAIL" >>$FILEPATH/$SCR.execs
							eval "$TARGET_CMD_FAIL"
						fi
					fi
				fi
			fi
		fi
	fi
done
# Done