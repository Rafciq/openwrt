#!/bin/sh
# Install or download packages and/or sysupgrade.
# Script version 1.16 Rafal Drzymala 2013
#
# Changelog
#
#	1.00	RD	First stable code
#	1.04	RD	Change code sequence
#	1.05	RD	Code tune up
#	1.06	RD	Code tune up
#	1.07	RD	ExtRoot code improvements
#	1.08	RD	Add image check sum control
#	1.09	RD	Add command line switch on/off-line package post-install
#				Add command line switch to disable configuration backup 
#	1.10	RD	Preparation scripts code improvements
#	1.11	RD	Preparation scripts code improvements (2)
#	1.12	RD	Preparation scripts code improvements (3)
#	1.13	RD	Preparation scripts code improvements (4)
#	1.14	RD	Extroot scripts code improvements
#	1.15	RD	Help improvements
#	1.16	RD	Help improvements (2), Preparation scripts code improvements (5)
#
# Destination /sbin/install.sh
#
local CMD
local OFFLINE_POST_INSTALL="1"
local HOST_NAME
local BACKUP_ENABLE="1"
local BACKUP_PATH
local BACKUP_FILE
local INSTALL_PATH="/tmp"
local PACKAGES
local DEPENDS
local IMAGE_SOURCE
local IMAGE_PREFIX
local IMAGE_SUFFIX
local IMAGE_FILENAME="sysupgrade.bin"
local POST_INSTALL_SCRIPT="post-installer"
local POST_INSTALLER="/bin/$POST_INSTALL_SCRIPT.sh"
local EXTROOT_BYPASS_SCRIPT="extroot-bypass"
local EXTROOT_BYPASSER="/bin/$EXTROOT_BYPASS_SCRIPT.sh"
local INSTALLER_KEEP_FILE="/lib/upgrade/keep.d/$POST_INSTALL_SCRIPT"
local RC_LOCAL="/etc/rc.local"
local BIN_LOGGER
local BIN_CAT
local BIN_RM
local BIN_SYNC
local BIN_REBOOT
local BIN_AWK
local BIN_OPKG
local BIN_SYSUPGRADE
local BIN_PING

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

print_help() {
	echo -e	"Usage:"\
			"\n\t$0 [install|download|sysupgrade] [-c|--config] [-h|--help] [-o|--online] [-b|--backup-off]"\
			"\n\nCommands:"\
			"\n\t\tdownload\tdownload all packages and system image do install directory."\
			"\n\t\tinstall\t\tbackup configuration,"\
			"\n\t\t\t\tstop and disable packages,"\
			"\n\t\t\t\tinstall packages,"\
			"\n\t\t\t\trestore configuration,"\
			"\n\t\t\t\tenable and start packages."\
			"\n\t\tsysupgrade\tbackup configuration,"\
			"\n\t\t\t\tdownload all packages and system image do install directory (in off-line mode),"\
			"\n\t\t\t\tprepare post upgrade package installer,"\
			"\n\t\t\t\tprepare extroot bypass script (if needed),"\
			"\n\t\t\t\tsystem upgrade,"\
			"\n\t\t\t\t... reboot system ...,"\
			"\n\t\t\t\tif extroot exist, clean check sum and reboot system,"\
			"\n\t\t\t\tinstall packages,"\
			"\n\t\t\t\trestore configuration,"\
			"\n\t\t\t\tcleanup installation,"\
			"\n\t\t\t\t... reboot system ..."\
			"\nOptions:"\
			"\n\t\t-h\t\tThis help"\
			"\n\t\t-c\t\tConfiguration"\
			"\n\t\t-b\t\tDisable configuration backup and restore during installation or system upgrade process."\
			"\n\t\t\t\tBy default, backup and restore configuration are enabled."\
			"\n\t\t\t\tPath to backup have to on external device otherwise during system upgrade can be lost."\
			"\n\t\t-o\t\tOnline packages installation by post-installer."\
			"\n\t\t\t\tInternet connection is needed after system restart and before packages installation."\
			"\nCurrent configuration:"\
			"\n\tLocal install directory : '$(uci -q get system.@sysupgrade[0].localinstall)'"\
			"\n\tConfiguration backup direcory : '$(uci -q get system.@sysupgrade[0].backupconfig)'"\
			"\n\tImage source URL : '$(uci -q get system.@sysupgrade[0].imagesource)'"\
			"\n\tImage source prefix : '$(uci -q get system.@sysupgrade[0].imageprefix)'"\
			"\n\tImage source suffix : '$(uci -q get system.@sysupgrade[0].imagesuffix)'"\
			"\n\tPackages: '$(uci -q get system.@sysupgrade[0].opkg)'"\
			"\n\nExamples configuration in /etc/config/system"\
			"\n\tconfig sysupgrade"\
			"\n\t\toption localinstall '/install'"\
			"\n\t\toption backupconfig '/backup'"\
			"\n\t\toption imagesource 'http://ecco.selfip.net/attitude_adjustment/ar71xx'"\
			"\n\t\toption imageprefix 'openwrt-ar71xx-generic-'"\
			"\n\t\toption imagesuffix '-squashfs-sysupgrade.bin'"\
			"\n\t\tlist opkg libusb"\
			"\n\t\tlist opkg kmod-usb-serial-option"\
			"\n\t\tlist opkg kmod-usb-net-cdc-ether"
	exit 0
}

initialize() {
	while [ -n "$1" ]; do
		case "$1" in
			install|download|sysupgrade) CMD="$1";; 
			-h|--help) print_help;;
			-b|--backup-off) BACKUP_ENABLE="";;
			-o|--online) OFFLINE_POST_INSTALL="";;
			-*) echo "Invalid option: $1";print_help;;
			*) echo "Invalid command: $1";print_help;;
		esac
	shift;
	done
	[ "$CMD" == "" ] && CMD=install
	HOST_NAME=$(uci -q get system.@system[0].hostname)
	if [ "$HOST_NAME" == "" ]; then 
		echo "Error while getting host name!"
		exit 1
	fi
	if [ "$CMD" == "download" ] || ([ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ]); then
		INSTALL_PATH=$(uci -q get system.@sysupgrade[0].localinstall)
		if [ "$INSTALL_PATH" == "" ]; then
			echo "Install path is empty!"
			exit 1
		fi	
		if [ ! -d "$INSTALL_PATH" ]; then
			echo "Install path not exist!"
			exit 1
		fi	
	fi
	if [ "$BACKUP_ENABLE" != "" ]; then
		BACKUP_PATH=$(uci -q get system.@sysupgrade[0].backupconfig)
		BACKUP_FILE="$BACKUP_PATH/backup-$HOST_NAME-$(date +%Y-%m-%d-%H-%M-%S).tar.gz"		
		if [ ! -d "$BACKUP_PATH" ]; then
			echo "Backup path not exist!"
			exit 1
		fi
		local MOUNT_DEVICE=$(get_mount_device $BACKUP_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			echo "Backup path ($BACKUP_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
	fi
	IMAGE_SOURCE=$(uci -q get system.@sysupgrade[0].imagesource)
	IMAGE_PREFIX=$(uci -q get system.@sysupgrade[0].imageprefix)
	IMAGE_SUFFIX=$(uci -q get system.@sysupgrade[0].imagesuffix)
	PACKAGES=$(uci -q get system.@sysupgrade[0].opkg)
	if [ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ]; then
		local MOUNT_DEVICE=$(get_mount_device $INSTALL_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			echo "Install path ($INSTALL_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
	fi
	which_binary BIN_LOGGER logger
	which_binary BIN_CAT cat
	which_binary BIN_RM rm
	which_binary BIN_SYNC sync
	which_binary BIN_REBOOT reboot
	which_binary BIN_AWK awk
	which_binary BIN_OPKG opkg
	which_binary BIN_SYSUPGRADE sysupgrade
	which_binary BIN_PING ping
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
	if [ "$BACKUP_ENABLE" != "" ]; then
		if [ ! -d "$BACKUP_PATH" ]; then
			echo "Backup path not exist."
			exit 1
		fi
		if [ "$BACKUP_FILE" == "" ]; then
			echo "Backup file name is empty."
			exit 1
		fi
		echo "Making configuration backup to $BACKUP_FILE ..."
		sysupgrade --create-backup $BACKUP_FILE
		check_exit_code
		chmod 640 $BACKUP_FILE
		check_exit_code
		echo "Configuration backuped."
	fi
}

config_restore() {
	if [ "$BACKUP_ENABLE" != "" ]; then
		if [ "$BACKUP_FILE" == "" ]; then
			echo "Backup file name is empty."
			exit 1
		else
			echo "Restoring configuration from backup $BACKUP_FILE ..."
			sysupgrade --restore-backup $BACKUP_FILE
			check_exit_code
			echo "Configuration restored."
		fi
	fi
}

packages_disable() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Disabling packages ..."
		for PACKAGE in $PACKAGES; do
			package_execute_cmd $PACKAGE disable
			package_execute_cmd $PACKAGE stop
		done
		echo "Packages are disabled."
	fi
}

packages_enable() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Enabling packages ..."
		for PACKAGE in $PACKAGES; do
			package_execute_cmd $PACKAGE enable
			package_execute_cmd $PACKAGE start
		done
		echo "Packages are enabled."
	fi
}

packages_install() {
	if [ "$PACKAGES" != "" ]; then 
		echo "Installing packages ..."
		opkg $CMD $PACKAGES
		check_exit_code
		echo "Packages are installed."
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
			echo "Getting information for package $PACKAGE."
			opkg info $PACKAGE >>$INSTALL_PATH/$PACKAGES_FILE
			check_exit_code
		done 
		echo "Compressing packages information as $INSTALL_PATH/$PACKAGES_LIST ..."
		awk '{if($0!~/^Status\:|^Installed-Time\:/)print $0}' $INSTALL_PATH/$PACKAGES_FILE | gzip -c9 >$INSTALL_PATH/$PACKAGES_LIST
		check_exit_code
		rm -f $INSTALL_PATH/$PACKAGES_FILE
		check_exit_code
		echo "Packages are downloaded."
	fi
}

image_download() {
	if [ "$IMAGE_SOURCE" == "" ] || [ "$IMAGE_PREFIX" == "" ] || [ "$IMAGE_SUFFIX" == "" ]; then 
		echo "Image source information is empty."
		exit 1
	fi
	local IMAGE_REMOTE_NAME="$IMAGE_SOURCE/$IMAGE_PREFIX$(system_board_name)$IMAGE_SUFFIX"
	local IMAGE_LOCAL_NAME="$INSTALL_PATH/$IMAGE_FILENAME"
	local SUMS_REMOTE_NAME="$IMAGE_SOURCE/md5sums"
	local SUMS_LOCAL_NAME="$INSTALL_PATH/md5sums"
		[ -f $IMAGE_LOCAL_NAME ] && rm -f $IMAGE_LOCAL_NAME
	echo "Downloading system image as $IMAGE_LOCAL_NAME from $IMAGE_REMOTE_NAME ..."	
	wget -O $IMAGE_LOCAL_NAME $IMAGE_REMOTE_NAME
	check_exit_code
	echo "Downloading images sums as $SUMS_LOCAL_NAME from $SUMS_REMOTE_NAME ..."	
	wget -O $SUMS_LOCAL_NAME $SUMS_REMOTE_NAME
	echo "Checking system image control sum ..."	
	check_exit_code
	local SUM_ORG=$(grep $(basename $IMAGE_REMOTE_NAME) $SUMS_LOCAL_NAME | cut -d " " -f 1)
	check_exit_code
	local SUM_FILE=$(md5sum $IMAGE_LOCAL_NAME | cut -d " " -f 1)
	check_exit_code
	if [ "$SUM_ORG" == "" ]; then
		echo "Can't get original control sum!"
		exit 1
	elif [ "$SUM_FILE" == "" ]; then
		echo "Can't calculate system image control sum!"
		exit 1
	elif [ "$SUM_ORG" != "$SUM_FILE" ]; then
		echo "Downloaded system image is damaged!"
		exit 1
	else
		echo "System image is downloaded and checksum is correct."
	fi
}

extroot_preapre() {
	local EXTROOT_CONFIG=$(uci show fstab | grep .is_rootfs | cut -d. -f2)
	local EXTROOT_ENABLED="0"
	[ "$EXTROOT_CONFIG" != "" ] && EXTROOT_ENABLED=$(uci -q get fstab.$EXTROOT_CONFIG.is_rootfs)
	if [ "$EXTROOT_ENABLED" == "1" ]; then
		echo "Preparing extroot bypass $EXTROOT_BYPASSER ..."
		add_to_keep_file "$EXTROOT_BYPASSER"
		echo -e	"#!/bin/sh"\
				"\n# Script auto-generated by $0"\
				"\nlocal AT_END"\
				"\n$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Start extroot bypass\""\
				"\nif [ -d /tmp/overlay-disabled ]; then"\
				"\n\t$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Removing overlay-rootfs checksum\""\
				"\n\t$BIN_RM -f /tmp/overlay-disabled/.extroot.md5sum"\
				"\n\t$BIN_RM -f /tmp/overlay-disabled/etc/extroot.md5sum"\
				"\n\tAT_END=\"$BIN_SYNC;$BIN_REBOOT -f\""\
				"\nelif [ -d /tmp/whole_root-disabled ]; then"\
				"\n\t$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Removing whole-rootfs checksum\""\
				"\n\t$BIN_RM -f /tmp/whole_root-disabled/.extroot.md5sum"\
				"\n\t$BIN_RM -f /tmp/whole_root-disabled/etc/extroot.md5sum"\
				"\n\tAT_END=\"$BIN_SYNC;$BIN_REBOOT -f\""\
				"\nelif [ -x \"$POST_INSTALLER\" ]; then"\
				"\n\t$POST_INSTALLER &\n"\
				"\nfi"\
				"\n$BIN_LOGGER -p user.notice -t $EXTROOT_BYPASS_SCRIPT \"Stop extroot bypass, cleaning and force reboot if need\""\
				"\n$BIN_CAT $RC_LOCAL | $BIN_AWK -v installer=\"$EXTROOT_BYPASSER\" '\$0!~installer' >$RC_LOCAL"\
				"\n$BIN_RM -f $EXTROOT_BYPASSER"\
				"\n[ -n \"\$AT_END\" ] && \$AT_END"\
				"\n# Done.">$EXTROOT_BYPASSER
		check_exit_code
		chmod 777 $EXTROOT_BYPASSER
		check_exit_code
		echo "Setting next boot autorun extroot bypass ..."
		echo -e "[ -x $EXTROOT_BYPASSER ] && $EXTROOT_BYPASSER\n$(cat $RC_LOCAL)">$RC_LOCAL
		check_exit_code
		echo "Extroot bypass prepared."
	fi
}

installer_prepare() {
	echo "Preparing packages installer $POST_INSTALLER ..."
	add_to_keep_file "$POST_INSTALLER"
	echo -e	"#!/bin/sh"\
			"\n# Script auto-generated by $0"\
			"\nlocal PACKAGES=\"$PACKAGES\""\
			"\nlocal PACKAGE"\
			"\n$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Start instalation of packages\"">$POST_INSTALLER
	check_exit_code
	if [ "$OFFLINE_POST_INSTALL" != "" ]; then
		echo -e "$BIN_CAT /etc/opkg.conf | $BIN_AWK 'BEGIN{print \"src/gz local file:/$INSTALL_PATH\"}!/^src/{print \$0}' >/etc/opkg.conf">>$POST_INSTALLER
		check_exit_code
	else
		echo -e	"until $BIN_PING -q -W 30 -c 1 8.8.8.8 &>/dev/null; do"\
				"\n\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Wait for internet connection\""\
				"\ndone">>$POST_INSTALLER
		check_exit_code
	fi
	echo -e "$BIN_OPKG update | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT"\
			"\nfor PACKAGE in \$PACKAGES; do"\
			"\n\t$BIN_OPKG install \$PACKAGE | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT"\
			"\n\t[ -x /etc/init.d/\$PACKAGE ] && /etc/init.d/\$PACKAGE enable | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT"\
			"\ndone">>$POST_INSTALLER
	check_exit_code
	if [ "$BACKUP_ENABLE" != "" ]; then
		echo -e	"$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Restoring configuration backup from $BACKUP_FILE\""\
				"\n$BIN_SYSUPGRADE --restore-backup $BACKUP_FILE">>$POST_INSTALLER
		check_exit_code
	fi
	echo -e	"$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Stop instalation of packages, cleaning and force reboot\""\
			"\n$BIN_RM -f $INSTALLER_KEEP_FILE"\
			"\n$BIN_CAT $RC_LOCAL | $BIN_AWK -v installer=\"$POST_INSTALLER\" '\$0!~installer' >$RC_LOCAL"\
			"\n$BIN_RM -f $POST_INSTALLER"\
			"\n$BIN_SYNC"\
			"\n# $BIN_REBOOT -f"\
			"\n# Done.">>$POST_INSTALLER
	check_exit_code
	chmod 777 $POST_INSTALLER
	check_exit_code
	echo "Setting next boot autorun packages installer ..."
	#add_to_keep_file "$RC_LOCAL"
	echo -e "[ -x $POST_INSTALLER ] && $POST_INSTALLER &\n$(cat $RC_LOCAL)">$RC_LOCAL
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
if [ "$CMD" == "download" ] || ([ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ]); then
	packages_download
fi
[ "$CMD" == "install" ] && config_restore && packages_enable
if [ "$CMD" == "download" ] || [ "$CMD" == "sysupgrade" ]; then
	image_download
fi
[ "$CMD" == "sysupgrade" ] && installer_prepare && sysupgrade_execute
echo "Done."
# Done.
