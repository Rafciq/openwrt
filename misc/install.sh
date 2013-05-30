#!/bin/sh
# Install or download packages and/or sysupgrade.
# Script version 1.07 Rafal Drzymala 2013
#
# Changelog
#
#	1.00	RD	First stable code
#	1.04	RD	Change code sequence
#	1.05	RD	Code tune up
#	1.06	RD	Code tune up
#	1.07	RD	ExtRoot code improvments
#
# Usage
#	install.sh download 
#			download all packages and system image do install directory
#
#	install.sh install
#			backup config,
#			stop and packages disable, 
#			install packages,
#			restore config,
#			enable and start packages
#
#	install.sh sysupgrade 
#			backup config,
#			download all packages and system image do install directory
#			prepare port upgrade package installer (prepare extroot bypass script)
#			system upgrade
#			... reboot system ...
#			if extroot exist, clean check sum and reboot system
#			install packages,
#			restore config,
#			cleanup installation
#			... reboot system ...
#
# Examples configuration in /etc/config/system
#
#	config sysupgrade
#		option localinstall '/install'
#		option backupconfig '/backup'
#		option imagesource 'http://ecco.selfip.net/attitude_adjustment/ar71xx'
#		option imageprefix 'openwrt-ar71xx-generic-'
#		option imagesuffix '-squashfs-sysupgrade.bin'
#		list opkg libusb 
#		list opkg kmod-usb-serial-option 
#		list opkg kmod-usb-net-cdc-ether 
#		list opkg usb-modeswitch-data 
#		list opkg chat 
#		list opkg comgt
#		list opkg ntpclient 
#
# Destination /sbin/install.sh
#

local CMD
local HOST_NAME
local BACKUP_PATH
local INSTALL_PATH
local PACKAGES
local DEPENDS
local IMAGE_SOURCE
local IMAGE_PREFIX
local IMAGE_SUFFIX
local IMAGE_FILENAME="sysupgrade.bin"
local BACKUP_FILE
local POST_INSTALL_SCRIPT="post-installer"
local POST_INSTALLER="/bin/$POST_INSTALL_SCRIPT.sh"
local EXTROOT_BYPASS_SCRIPT="bypass-installer"
local EXTROOT_BYPASSER="/bin/$EXTROOT_BYPASS_SCRIPT.sh"
local INSTALLER_KEEP_FILE="/lib/upgrade/keep.d/$POST_INSTALL_SCRIPT"
local RC_LOCAL="/etc/rc.local"
local BIN_LOGGER
local BIN_CAT
local BIN_RM
local BIN_REBOOT
local BIN_AWK
local BIN_OPKG
local BIN_SYSUPGRADE

check_exit_code() {
	local CODE=$?
	if [ $CODE != 0 ]; then 
		echo "Abort, error ($CODE) detected!"
		exit $CODE
	fi
}

get_mount_device() {
	local CHECK_PATH=$1
	[ -L $CHECK_PATH ] && CHECK_PATH=$(ls -l $CHECK_PATH | awk -F " -> " '{print $2}')
	echo $(awk -v path="$CHECK_PATH" 'BEGIN{FS=" ";device=""}path~"^"$2{if($2>point){device=$1;point=$2}}END{print device}' /proc/mounts)
	check_exit_code
}

which_binary() {
	local VARIABLE="$1"
	local BINARY="$2"
	local WHICH=$(which $BINARY)
	if [ "$WHICH" == "" ]; then
		echo "Binary $BINARY not found in system!"
		exit 1
	else
		eval "export -- \"$VARIABLE=$WHICH\""
	fi
}

add_to_keep_file() {
	echo "$1">>$INSTALLER_KEEP_FILE
	check_exit_code
}

package_execute_cmd() {
	local PACKAGE="$1"
	local CMD="$2"
	if [ -x /etc/init.d/$PACKAGE ]; then
		echo "Executing $PACKAGE $CMD"
		if [ "$CMD" == "enable" ]; then
			/etc/init.d/$PACKAGE $CMD
		else
			/etc/init.d/$PACKAGE $CMD
			check_exit_code
		fi
	fi
}

system_board_name() {
	local BOARD_NAME=$(cat /tmp/sysinfo/model | tr '[A-Z]' '[a-z]')
	local BOARD_VER=$(echo "$BOARD_NAME" | cut -d " " -f 3)
	BOARD_NAME=$(echo "$BOARD_NAME" | cut -d " " -f 2)
	[ "$BOARD_VER" == "" ] || BOARD_VER="-$BOARD_VER"
	if [ "$BOARD_NAME$BOARD_VER" == "" ]; then 
		echo "Error while getting system board name"
		exit 1
	fi
	echo "$BOARD_NAME$BOARD_VER"
}

caution_alert() {
	local KEY
	echo "Caution!"
	echo "You can damage the system or hardware. You perform this operation at your own risk."
	read -t 60 -n 1 -p "Press Y to continue " KEY
	echo ""
	[ "$KEY" != "Y" ] && exit 0
}

initialize() {
	CMD="$1"
	[ "$CMD" == "" ] && CMD=install
	if [ "$CMD" != "install" ] && [ "$CMD" != "download" ] && [ "$CMD" != "sysupgrade" ]; then
		echo "Invalid command $CMD"
		echo "Usage:"
		echo "	$0 [install|download|sysupgrade]"
		exit 0
	fi
	HOST_NAME=$(uci -q get system.@system[0].hostname)
	if [ "$HOST_NAME" == "" ]; then 
		echo "Error while getting host name"
		exit 1
	fi
	INSTALL_PATH=$(uci -q get system.@sysupgrade[0].localinstall)
	if [ "$INSTALL_PATH" == "" ]; then
		echo "Install path is empty."
		exit 1
	fi	
	if [ ! -d "$INSTALL_PATH" ]; then
		echo "Install path not exist."
		exit 1
	fi	
	BACKUP_PATH=$(uci -q get system.@sysupgrade[0].backupconfig)
	BACKUP_FILE="$BACKUP_PATH/backup-$HOST_NAME-$(date +%Y-%m-%d-%H-%M-%S).tar.gz"		
	IMAGE_SOURCE=$(uci -q get system.@sysupgrade[0].imagesource)
	IMAGE_PREFIX=$(uci -q get system.@sysupgrade[0].imageprefix)
	IMAGE_SUFFIX=$(uci -q get system.@sysupgrade[0].imagesuffix)
	PACKAGES=$(uci -q get system.@sysupgrade[0].opkg)
	if [ "$CMD" == "sysupgrade" ]; then
		local MOUNT_DEVICE=$(get_mount_device $INSTALL_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			echo "Install path ($INSTALL_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
		if [ ! -d "$BACKUP_PATH" ]; then
			echo "Backup path not exist."
			exit 1
		fi
		MOUNT_DEVICE=$(get_mount_device $BACKUP_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			echo "Backup path ($BACKUP_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
	fi
	which_binary BIN_LOGGER logger
	which_binary BIN_CAT cat
	which_binary BIN_RM rm
	which_binary BIN_REBOOT reboot
	which_binary BIN_AWK awk
	which_binary BIN_OPKG opkg
	which_binary BIN_SYSUPGRADE sysupgrade
	echo "Operation $CMD on $HOST_NAME"
}

update_repository() {
	echo "Updating packages repository ..."
	opkg update
	check_exit_code
	echo "Packages repository updated."
}

check_dependency() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Checking packages dependency ..."
		DEPENDS=$(opkg depends -A $PACKAGES | awk -v PKG="$PACKAGES " '$2==""{ORS=" ";if(!seen[$1]++ && index(PKG,$1" ")==0)print $1}')
		check_exit_code
		echo "Packages: $PACKAGES."
		[ "$DEPENDS" != "" ] && echo "Depends: $DEPENDS."
	fi
}

config_backup() {
	if [ ! -d "$BACKUP_PATH" ]; then
		echo "Backup path not exist."
		exit 1
	fi
	if [ "$BACKUP_FILE" == "" ]; then
		echo "Backup file name is empty."
		exit 1
	fi
	echo "Making config backup to $BACKUP_FILE ..."
	sysupgrade --create-backup $BACKUP_FILE
	check_exit_code
	chmod 640 $BACKUP_FILE
	check_exit_code
	echo "Config backuped."
}

config_restore() {
	if [ "$BACKUP_FILE" == "" ]; then
		echo "Backup file name is empty."
		exit 1
	else
		echo "Restoring config backup from $BACKUP_FILE ..."
		sysupgrade --restore-backup $BACKUP_FILE
		check_exit_code
		echo "Config restored."
	fi
}

packages_disable() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Disabling packages ..."
		for PACKAGE in $PACKAGES; do
			package_execute_cmd $PACKAGE disable
			package_execute_cmd $PACKAGE stop
		done
		echo "Packages disabled."
	fi
}

packages_enable() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Enabling packages ..."
		for PACKAGE in $PACKAGES; do
			package_execute_cmd $PACKAGE enable
			package_execute_cmd $PACKAGE start
		done
		echo "Packages enabled."
	fi
}

packages_install() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Installing packages ..."
		opkg $CMD $PACKAGES
		check_exit_code
		echo "Packages installed."
	fi
}

packages_download() {
	if [ "$PACKAGES$DEPENDS" != "" ]; then 
		local PACKAGES_FILE="Packages"
		local PACKAGES_LIST="$PACKAGES_FILE.gz"
		echo "Downloading packages to $INSTALL_PATH ..."
		cd $INSTALL_PATH
		rm -f *.ipk
		opkg download $PACKAGES $DEPENDS
		check_exit_code
		echo "Building packages information ..."
		[ -f $INSTALL_PATH/$PACKAGES_FILE ] && rm -f $INSTALL_PATH/$PACKAGES_FILE
		[ -f $INSTALL_PATH/$PACKAGES_LIST ] && rm -f $INSTALL_PATH/$PACKAGES_LIST
		for PACKAGE in $PACKAGES $DEPENDS; do
			echo "Getting packages information for $PACKAGE."
			opkg info $PACKAGE >>$INSTALL_PATH/$PACKAGES_FILE
			check_exit_code
		done 
		echo "Compressing packages information as $INSTALL_PATH/$PACKAGES_LIST ..."
		awk '{if($0!~/^Status\:|^Installed-Time\:/)print $0}' $INSTALL_PATH/$PACKAGES_FILE | gzip -c9 >$INSTALL_PATH/$PACKAGES_LIST
		check_exit_code
		rm -f $INSTALL_PATH/$PACKAGES_FILE
		check_exit_code
		echo "Packages downloaded."
	fi
}

image_download() {
	if [ "$IMAGE_SOURCE" == "" ] || [ "$IMAGE_PREFIX" == "" ] || [ "$IMAGE_SUFFIX" == "" ]; then 
		echo "Image source information is empty."
		exit 1
	fi
	local IMAGE_REMOTE_NAME="$IMAGE_SOURCE/$IMAGE_PREFIX$(system_board_name)$IMAGE_SUFFIX"
	local IMAGE_LOCAL_NAME="$INSTALL_PATH/$IMAGE_FILENAME"
	[ -f $IMAGE_LOCAL_NAME ] && rm -f $IMAGE_LOCAL_NAME
	echo "Downloading system image as $IMAGE_LOCAL_NAME from $IMAGE_REMOTE_NAME ..."	
	wget -O $IMAGE_LOCAL_NAME $IMAGE_REMOTE_NAME
	check_exit_code
	echo "System image downloaded."
}

extroot_preapre() {
	local EXTROOT_CONFIG=$(uci show fstab | grep .is_rootfs | cut -d. -f2)
	local EXTROOT_ENABLED="0"
	[ "$EXTROOT_CONFIG" != "" ] && EXTROOT_ENABLED=$(uci -q get fstab.$EXTROOT_CONFIG.is_rootfs)
	if [ "$EXTROOT_ENABLED" == "1" ]; then
		echo "Preparing extroot bypass $EXTROOT_BYPASSER ..."
		add_to_keep_file "$EXTROOT_BYPASSER"
		echo -e	"#!/bin/sh\n" \
				"# Script auto-generated by $0\n" \
				"local AT_END\n" \
				"$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Start extroot bypass\"\n" \
				"if [ -d /tmp/overlay-disabled ]; then\n" \
				"	$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Removing overlay-rootfs checksum\"\n" \
				"	$BIN_RM -f /tmp/overlay-disabled/.extroot.md5sum\n" \
				"	$BIN_RM -f /tmp/overlay-disabled/etc/extroot.md5sum\n" \
				"	AT_END=\"$BIN_REBOOT -f\"\n" \
				"elif [ -d /tmp/whole_root-disabled ]; then\n" \
				"	$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Removing whole-rootfs checksum\"\n" \
				"	$BIN_RM -f /tmp/whole_root-disabled/.extroot.md5sum\n" \
				"	$BIN_RM -f /tmp/whole_root-disabled/etc/extroot.md5sum\n" \
				"	AT_END=\"$BIN_REBOOT -f\"\n" \
				"elif [ -x \"$POST_INSTALLER\" ]; then\n" \
				"	$POST_INSTALLER &\n"
				"fi\n" \
				"$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Stop extroot bypass, cleaning and force reboot if need\"\n" \
				"$BIN_RM -f $EXTROOT_BYPASSER;[ -n \"\$AT_END\" ] && \$AT_END\n" \
				"# Done.">$EXTROOT_BYPASSER
		check_exit_code
		chmod 777 $EXTROOT_BYPASSER
		check_exit_code
		echo "Setting next boot autorun extroot bypass ..."
		echo -e "$EXTROOT_BYPASSER\n$(cat $MOUNT_POINT$RC_LOCAL)">$RC_LOCAL
		check_exit_code
		echo "Extroot bypass prepared."
	fi
}

installer_prepare() {
	echo "Preparing packages installer $POST_INSTALLER ..."
	add_to_keep_file "$POST_INSTALLER"
	echo -e	"#!/bin/sh\n" \
			"# Script auto-generated by $0\n" \
			"local PACKAGES=\"$PACKAGES\"\n" \
			"local PACKAGE\n" \
			"$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Start instalation of packages\"\n" \
			"$BIN_CAT /etc/opkg.conf | $BIN_AWK 'BEGIN{print \"src/gz local file:/$INSTALL_PATH\"}!/^src/{print \$0}' >/etc/opkg.conf\n" \
			"$BIN_OPKG update | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT\n" \
			"for PACKAGE in \$PACKAGES; do\n" \
			"	$BIN_OPKG install \$PACKAGE | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT\n" \
			"	[ -x /etc/init.d/\$PACKAGE ] && /etc/init.d/\$PACKAGE enable | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT\n" \
			"done\n" \
			"$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Restoring config backup from $BACKUP_FILE\"\n" \
			"$BIN_SYSUPGRADE --restore-backup $BACKUP_FILE\n" \
			"$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Stop instalation of packages, cleaning and force reboot\"\n" \
			"$BIN_RM -f $INSTALLER_KEEP_FILE\n" \
			"$BIN_RM -f $POST_INSTALLER;$BIN_REBOOT -f\n" \
			"# Done.">$POST_INSTALLER
	check_exit_code
	chmod 777 $POST_INSTALLER
	check_exit_code
	echo "Setting next boot autorun packages installer ..."
	add_to_keep_file "$RC_LOCAL"
	echo -e "$POST_INSTALLER &\n$(cat $RC_LOCAL)">$RC_LOCAL
	check_exit_code
	echo "Packages installer prepared."
	extroot_preapre
}

sysupgrade_execute() {
	echo "Upgrading system from image $INSTALL_PATH/$IMAGE_FILENAME ..."
	cd $INSTALL_PATH
	sysupgrade $IMAGE_FILENAME
}

# Main routine
initialize $@
[ "$CMD" == "sysupgrade" ] && caution_alert
update_repository
check_dependency
if [ "$CMD" == "install" ] || [ "$CMD" == "sysupgrade" ]; then
	config_backup
fi
[ "$CMD" == "install" ] && packages_disable && packages_install
if [ "$CMD" == "download" ]  || [ "$CMD" == "sysupgrade" ]; then
	packages_download
fi
[ "$CMD" == "install" ] && config_restore && packages_enable
if [ "$CMD" == "download" ] || [ "$CMD" == "sysupgrade" ]; then
	image_download
fi
[ "$CMD" == "sysupgrade" ] && installer_prepare && sysupgrade_execute
echo "Done."
# Done.