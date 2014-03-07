#!/bin/sh
# Install or download packages and/or sysupgrade.
# Script version 1.33 Rafal Drzymala 2013
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
#	1.17	RD	Extroot scripts code improvements (2)
#	1.18	RD	Include installed packages options
#	1.19	RD	Extroot scripts code improvements (3)
#	1.20	RD	Add status led toggle
#	1.21	RD	Correct rc.local manipulation code
#	1.22	RD	Add packages disabling to sysupgrade process
#				Preparation scripts code improvements (5)
#	1.23	RD	Extroot scripts code improvements
#	1.24	RD	Added recurrence of checking of package dependences
#				Changed packages initialization script name convention
#	1.25	RD	Preparation scripts code improvements (6)
#	1.26	RD	Preparation scripts code improvements (7)
#	1.27	RD	Code tune up
#	1.28	RD	Code tune up
#	1.29	RD	Dependency check code improvements
#	1.30	RD	Added post install file removing
#				Added external script
#	1.31	RD	Added backup command
#	1.32	RD	Removed I/O control after post install file removing
#	1.33	RD	Added variables to image source path
#
# Destination /sbin/install.sh
#
. /etc/openwrt_release

local CMD=""
local OFFLINE_POST_INSTALL="1"
local INCLUDE_INSTALLED="1"
local HOST_NAME=""
local BACKUP_ENABLE="1"
local BACKUP_PATH=""
local BACKUP_FILE=""
local INSTALL_PATH="/tmp"
local PACKAGES=""
local IMAGE_SOURCE=""
local IMAGE_FILENAME="sysupgrade.bin"
local POST_INSTALL_SCRIPT="post-installer"
local POST_INSTALLER="/bin/$POST_INSTALL_SCRIPT.sh"
local POST_INSTALLER_LOG="/usr/$POST_INSTALL_SCRIPT.log"
local INSTALLER_KEEP_FILE="/lib/upgrade/keep.d/$POST_INSTALL_SCRIPT"
local RC_LOCAL="/etc/rc.local"
local POST_INSTALL_REMOVE="/etc/config/*-opkg"
local RUN_SCRIPT=""

check_exit_code() {
	local CODE=$?
	if [ $CODE != 0 ]; then 
		echo "Abort, error ($CODE) detected!"
		exit $CODE
	fi
}

get_mount_device() { # <Path to check>
	local CHECK_PATH=$1
	[ -L $CHECK_PATH ] && CHECK_PATH=$($BIN_LS -l $CHECK_PATH | $BIN_AWK -F " -> " '{print $2}')
	$BIN_AWK -v path="$CHECK_PATH" 'BEGIN{FS=" ";device=""}path~"^"$2{if($2>point){device=$1;point=$2}}END{print device}' /proc/mounts
	check_exit_code
}

which_binary() { # <Name of Binary> [<Name of Binary> [...]]
	while [ -n "$1" ]; do
		local WHICH=$(which $1)
		if [ "$WHICH" == "" ]; then
			echo "Binary $1 not found in system!"
			exit 1
		else
			eval "export -- \"BIN_$(echo $1 | tr '[a-z]' '[A-Z]')=$WHICH\""
		fi
		shift
	done
}

add_to_keep_file() { # <Content to save> <Root path>
	local CONTENT="$1"
	local ROOT_PATH="$2"
	$BIN_ECHO "$1">>$ROOT_PATH$INSTALLER_KEEP_FILE
	check_exit_code
}

run_script() { # <Event>
	if [ "$RUN_SCRIPT" != "" ] && [ -x $RUN_SCRIPT ]; then
		$BIN_ECHO "Run script $RUN_SCRIPT $1 ..."
		$RUN_SCRIPT $1
		check_exit_code
		$BIN_ECHO "Script $RUN_SCRIPT exited."
	fi
}

add_to_post_installer_log() { # <Content to save>
	$BIN_ECHO "$($BIN_DATE) $1">>$POST_INSTALLER_LOG
}

package_script_execute() { # <Package> <Script name> <Command>
	local PACKAGE="$1"
	local SCRIPT="$2"
	local CMD="$3"
	if [ -x $SCRIPT ]; then
		$BIN_ECHO "Executing $SCRIPT $CMD for package $PACKAGE"
		if [ "$CMD" == "enable" ] || [ "$CMD" == "stop" ]; then
			$SCRIPT $CMD
		else
			$SCRIPT $CMD
			check_exit_code
		fi
	fi
}

update_path_vars() { # <String to update>
	local PATH_VARS="$1"
	local TARGET=$(echo "$DISTRIB_TARGET" | cut -d "/" -f 1)
	local SUBTARGET=$(echo "$DISTRIB_TARGET" | cut -d "/" -f 2)
	local BOARD_NAME=$($BIN_CAT /tmp/sysinfo/model | $BIN_TR '[A-Z]' '[a-z]')
	local BOARD_VER=$($BIN_ECHO "$BOARD_NAME" | $BIN_CUT -d " " -f 3)
	BOARD_NAME=$($BIN_ECHO "$BOARD_NAME" | $BIN_CUT -d " " -f 2)
	[ -n "$BOARD_VER" ] && BOARD_NAME="$BOARD_NAME-$BOARD_VER"
	[ -n "$DISTRIB_CODENAME" ] && PATH_VARS=${PATH_VARS//\<CODENAME\>/$DISTRIB_CODENAME}
	[ -n "$TARGET" ] && PATH_VARS=${PATH_VARS//\<TARGET\>/$TARGET}
	[ -n "$SUBTARGET" ] && PATH_VARS=${PATH_VARS//\<SUBTARGET\>/$SUBTARGET}
	[ -n "$BOARD_NAME" ] && PATH_VARS=${PATH_VARS//\<HARDWARE\>/$BOARD_NAME}
	$BIN_ECHO "$PATH_VARS"
}

caution_alert() {
	local KEY
	$BIN_ECHO "Caution!"
	$BIN_ECHO "You can damage the system or hardware. You perform this operation at your own risk."
	read -t 60 -n 1 -p "Press Y to continue " KEY
	$BIN_ECHO ""
	[ "$KEY" != "Y" ] && exit 0
}

print_help() {
	$BIN_ECHO -e "Usage:"\
			"\n\t$0 [install|download|sysupgrade] [-h|--help] [-o|--online] [-b|--backup-off] [-i|--exclude-installed]"\
			"\n\nCommands:"\
			"\n\t\tdownload\tdownload all packages and system image do install directory,"\
			"\n\t\tinstall\t\tbackup configuration,"\
			"\n\t\t\t\tstop and disable packages,"\
			"\n\t\t\t\tinstall packages,"\
			"\n\t\t\t\trestore configuration,"\
			"\n\t\t\t\tenable and start packages."\
			"\n\t\tsysupgrade\tbackup configuration,"\
			"\n\t\t\t\tdownload all packages and system image do install directory (in off-line mode),"\
			"\n\t\t\t\tprepare post upgrade package installer,"\
			"\n\t\t\t\tsystem upgrade,"\
			"\n\t\t\t\t... reboot system ...,"\
			"\n\t\t\t\tif extroot exist, clean check sum and reboot system,"\
			"\n\t\t\t\tinstall packages,"\
			"\n\t\t\t\trestore configuration,"\
			"\n\t\t\t\tcleanup installation,"\
			"\n\t\t\t\t... reboot system ..."\
			"\n\t\tbackup\t\tbackup configuration"\
			"\n\nOptions:"\
			"\n\t\t-h\t\tThis help,"\
			"\n\t\t-b\t\tDisable configuration backup and restore during installation or system upgrade process."\
			"\n\t\t\t\tBy default, backup and restore configuration are enabled."\
			"\n\t\t\t\tPath to backup have to on external device otherwise during system upgrade can be lost."\
			"\n\t\t-o\t\tOnline packages installation by post-installer."\
			"\n\t\t\t\tInternet connection is needed after system restart and before packages installation."\
			"\n\t\t-i\t\tExclude installed packages. Only packages from configuration can be processed."\
			"\n\nCurrent configuration:"\
			"\n\tLocal install directory : '$($BIN_UCI -q get system.@sysupgrade[0].localinstall)'"\
			"\n\tConfiguration backup direcory : '$($BIN_UCI -q get system.@sysupgrade[0].backupconfig)'"\
			"\n\tImage source URL : '$($BIN_UCI -q get system.@sysupgrade[0].imagesource)'"\
			"\n\tRun external script : '$($BIN_UCI -q get system.@sysupgrade[0].runscript)'"\
			"\n\tPackages: '$($BIN_UCI -q get system.@sysupgrade[0].opkg)'"\
			"\n\nExamples configuration in /etc/config/system"\
			"\n\tconfig sysupgrade"\
			"\n\t\toption localinstall '/install'"\
			"\n\t\toption backupconfig '/backup'"\
			"\n\t\toption imagesource 'http://ecco.selfip.net/<CODENAME>/<TARGET>/openwrt-<TARGET>-<SUBTARGET>-<HARDWARE>-squashfs-sysupgrade.bin'"\
			"\n\t\tlist opkg libusb"\
			"\n\t\tlist opkg kmod-usb-serial-option"\
			"\n\t\tlist opkg kmod-usb-net-cdc-ether"\
			"\n"
	exit 0
}

initialize() { # <Script parametrs>
	which_binary echo basename dirname logger chmod uci date ls cat cut tr wc rm mv sync reboot awk grep wget opkg sysupgrade md5sum ping logread gzip
	while [ -n "$1" ]; do
		case "$1" in
			install|download|sysupgrade|backup) CMD="$1";; 
			-h|--help) print_help;;
			-b|--backup-off) BACKUP_ENABLE="";;
			-o|--online) OFFLINE_POST_INSTALL="";;
			-i|--exclude-installed) INCLUDE_INSTALLED="";;
			-*) $BIN_ECHO "Invalid option: $1";print_help;;
			*) $BIN_ECHO "Invalid command: $1";print_help;;
		esac
		shift
	done
	[ "$CMD" == "" ] && CMD=install
	[ "$CMD" == "backup" ] && BACKUP_ENABLE="1"
	HOST_NAME=$($BIN_UCI -q get system.@system[0].hostname)
	if [ "$HOST_NAME" == "" ]; then 
		$BIN_ECHO "Error while getting host name!"
		exit 1
	fi
	if [ "$CMD" == "download" ] || ([ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ]); then
		INSTALL_PATH=$($BIN_UCI -q get system.@sysupgrade[0].localinstall)
		if [ "$INSTALL_PATH" == "" ]; then
			$BIN_ECHO "Install path is empty!"
			exit 1
		fi	
		if [ ! -d "$INSTALL_PATH" ]; then
			$BIN_ECHO "Install path not exist!"
			exit 1
		fi	
	fi
	if [ "$BACKUP_ENABLE" != "" ]; then
		BACKUP_PATH=$($BIN_UCI -q get system.@sysupgrade[0].backupconfig)
		BACKUP_FILE="$BACKUP_PATH/backup-$HOST_NAME-$($BIN_DATE +%Y-%m-%d-%H-%M-%S).tar.gz"		
		if [ ! -d "$BACKUP_PATH" ]; then
			$BIN_ECHO "Backup path not exist!"
			exit 1
		fi
		local MOUNT_DEVICE=$(get_mount_device $BACKUP_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			$BIN_ECHO "Backup path ($BACKUP_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
	fi
	if [ "$CMD" == "download" ] || [ "$CMD" == "sysupgrade" ]; then
		IMAGE_SOURCE=$($BIN_UCI -q get system.@sysupgrade[0].imagesource)
		local IMAGE_PREFIX=$($BIN_UCI -q get system.@sysupgrade[0].imageprefix)
		local IMAGE_SUFFIX=$($BIN_UCI -q get system.@sysupgrade[0].imagesuffix)
		if [ -n "$IMAGE_PREFIX" ] || [ -n "$IMAGE_SUFFIX" ]; then
			IMAGE_SOURCE="$IMAGE_SOURCE/$IMAGE_PREFIX<HARDWARE>$IMAGE_SUFFIX"
		fi
	fi
	RUN_SCRIPT=$($BIN_UCI -q get system.@sysupgrade[0].runscript)
	PACKAGES=$($BIN_UCI -q get system.@sysupgrade[0].opkg)
	if [ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ]; then
		local MOUNT_DEVICE=$(get_mount_device $INSTALL_PATH)
		if [ "$MOUNT_DEVICE" == "rootfs" ] || [ "$MOUNT_DEVICE" == "sysfs" ] || [ "$MOUNT_DEVICE" == "tmpfs" ]; then
			$BIN_ECHO "Install path ($INSTALL_PATH) must be on external device. Now is mounted on $MOUNT_DEVICE."
			exit 1
		fi
	fi
	$BIN_ECHO "Operation $CMD on $HOST_NAME - $DISTRIB_ID $DISTRIB_RELEASE ($DISTRIB_REVISION)"
}

update_repository() {
	run_script before_opkg_update
	$BIN_ECHO "Updating packages repository ..."
	$BIN_OPKG update
	check_exit_code
	$BIN_ECHO "Packages repository updated."
}

check_installed() {
	if [ "$INCLUDE_INSTALLED" != "" ]; then
		$BIN_ECHO "Checking installed packages ..."
		local INSTALLED=$($BIN_AWK -v PKG="$PACKAGES " 'BEGIN{FS=": ";ORS=" "}/^Package\: /{Package=$2}/^Status\: / && /user installed/{if(index(PKG,Package" ")==0)print Package}' /usr/lib/opkg/status)
		check_exit_code
		INSTALLED=${INSTALLED%% }
		if [ "$INSTALLED" != "" ]; then
			$BIN_ECHO "Installed packages not in configuration: $INSTALLED."
			PACKAGES="$PACKAGES $INSTALLED"
		else
			$BIN_ECHO "All packages from configuration."
		fi
	fi
}

check_dependency() {
	if [ "$PACKAGES" != "" ]; then 
		$BIN_ECHO "Checking packages dependency ..."
		$BIN_ECHO "Main packages: $PACKAGES."
		local PACKAGES_COUNT=-1
		while [ "$($BIN_ECHO $PACKAGES | $BIN_WC -w)" != "$PACKAGES_COUNT" ]; do
			PACKAGES_COUNT=$($BIN_ECHO $PACKAGES | $BIN_WC -w)
			local DEPENDS
			local DEPENDS_COUNT=-1
			while [ "$($BIN_ECHO $DEPENDS | $BIN_WC -w)" != "$DEPENDS_COUNT" ]; do
				DEPENDS_COUNT=$($BIN_ECHO $DEPENDS | $BIN_WC -w)
				DEPENDS=$DEPENDS$($BIN_OPKG depends -A $DEPENDS $PACKAGES | $BIN_AWK -v PKG="$DEPENDS $PACKAGES " 'BEGIN{ORS=" "}{if($2=="" && !seen[$1]++ && index(PKG,$1" ")==0)print $1}')
				check_exit_code
			done
			DEPENDS=${DEPENDS%% }
			[ "$DEPENDS" != "" ] && PACKAGES="$DEPENDS $PACKAGES"
			PACKAGES=$($BIN_OPKG whatprovides -A $PACKAGES | $BIN_AWK -v PKG="$PACKAGES " 'function Select(){if(CNT<1)return;SEL=0;for(ITEM in LIST)if(index(PKG,LIST[ITEM]" ")!=0)SEL=ITEM;if(!seen[LIST[SEL]]++)print LIST[SEL];delete LIST;CNT=0}BEGIN{ORS=" "}{if($3!="")Select();else LIST[CNT++]=$1}END{Select()}')
			PACKAGES=${PACKAGES%% }
		done
		$BIN_ECHO "All packages: $PACKAGES."
	fi
}

config_backup() {
	if [ "$BACKUP_ENABLE" != "" ]; then
		if [ ! -d "$BACKUP_PATH" ]; then
			$BIN_ECHO "Backup path not exist."
			exit 1
		fi
		if [ "$BACKUP_FILE" == "" ]; then
			$BIN_ECHO "Backup file name is empty."
			exit 1
		fi
		$BIN_ECHO "Making configuration backup to $BACKUP_FILE ..."
		$BIN_SYSUPGRADE --create-backup $BACKUP_FILE
		check_exit_code
		$BIN_CHMOD 640 $BACKUP_FILE
		check_exit_code
		$BIN_ECHO "Configuration backuped."
	fi
}

config_restore() {
	if [ "$BACKUP_ENABLE" != "" ]; then
		if [ "$BACKUP_FILE" == "" ]; then
			$BIN_ECHO "Backup file name is empty."
			exit 1
		else
			$BIN_ECHO "Restoring configuration from backup $BACKUP_FILE ..."
			$BIN_SYSUPGRADE --restore-backup $BACKUP_FILE
			check_exit_code
			$BIN_ECHO "Configuration restored."
		fi
	fi
}

packages_disable() {
	if [ "$PACKAGES" != "" ]; then 
		$BIN_ECHO "Disabling packages ..."
		local SCRIPT
		for PACKAGE in $PACKAGES; do
			for SCRIPT in $($BIN_OPKG files $PACKAGE | $BIN_GREP /etc/init.d/); do
				package_script_execute $PACKAGE $SCRIPT disable
				package_script_execute $PACKAGE $SCRIPT stop
			done
		done
		$BIN_ECHO "Packages are disabled."
	fi
}

packages_enable() {
	if [ "$PACKAGES" != "" ]; then 
		$BIN_ECHO "Enabling packages ..."
		local SCRIPT
		for PACKAGE in $PACKAGES; do
			for SCRIPT in $($BIN_OPKG files $PACKAGE | $BIN_GREP /etc/init.d/); do
				package_script_execute $PACKAGE $SCRIPT enable
				package_script_execute $PACKAGE $SCRIPT start
			done
		done
		$BIN_ECHO "Packages are enabled."
	fi
}

packages_install() {
	if [ "$PACKAGES" != "" ]; then 
		run_script before_opkg_install
		$BIN_ECHO "Installing packages ..."
		$BIN_OPKG $CMD $PACKAGES
		check_exit_code
		$BIN_RM $POST_INSTALL_REMOVE
		$BIN_ECHO "Packages are installed."
		run_script after_opkg_install
	fi
}

packages_download() {
	if [ "$PACKAGES" != "" ]; then 
		local PACKAGES_FILE="Packages"
		local PACKAGES_LIST="$PACKAGES_FILE.gz"
		$BIN_ECHO "Downloading packages to $INSTALL_PATH ..."
		cd $INSTALL_PATH
		$BIN_RM -f *.ipk
		$BIN_OPKG download $PACKAGES
		check_exit_code
		$BIN_ECHO "Building packages information ..."
		[ -f $INSTALL_PATH/$PACKAGES_FILE ] && $BIN_RM -f $INSTALL_PATH/$PACKAGES_FILE
		[ -f $INSTALL_PATH/$PACKAGES_LIST ] && $BIN_RM -f $INSTALL_PATH/$PACKAGES_LIST
		for PACKAGE in $PACKAGES; do
			$BIN_ECHO "Getting information for package $PACKAGE."
			$BIN_OPKG info $PACKAGE >>$INSTALL_PATH/$PACKAGES_FILE
			check_exit_code
		done 
		$BIN_ECHO "Compressing packages information as $INSTALL_PATH/$PACKAGES_LIST ..."
		$BIN_AWK '{if($0!~/^Status\:|^Installed-Time\:/)print $0}' $INSTALL_PATH/$PACKAGES_FILE | $BIN_GZIP -c9 >$INSTALL_PATH/$PACKAGES_LIST
		check_exit_code
		$BIN_RM -f $INSTALL_PATH/$PACKAGES_FILE
		check_exit_code
		$BIN_ECHO "Packages are downloaded."
	fi
}

image_download() {
	if [ "$IMAGE_SOURCE" == "" ]; then 
		$BIN_ECHO "Image source information is empty."
		exit 1
	fi
	local IMAGE_REMOTE_NAME="$(update_path_vars $IMAGE_SOURCE)"
	local IMAGE_LOCAL_NAME="$INSTALL_PATH/$IMAGE_FILENAME"
	local SUMS_REMOTE_NAME="$($BIN_DIRNAME $IMAGE_REMOTE_NAME)/md5sums"
	local SUMS_LOCAL_NAME="$INSTALL_PATH/md5sums"
	[ -f $IMAGE_LOCAL_NAME ] && $BIN_RM -f $IMAGE_LOCAL_NAME
	$BIN_ECHO "Downloading system image as $IMAGE_LOCAL_NAME from $IMAGE_REMOTE_NAME ..."	
	$BIN_WGET -O $IMAGE_LOCAL_NAME $IMAGE_REMOTE_NAME
	check_exit_code
	$BIN_ECHO "Downloading images sums as $SUMS_LOCAL_NAME from $SUMS_REMOTE_NAME ..."	
	$BIN_WGET -O $SUMS_LOCAL_NAME $SUMS_REMOTE_NAME
	check_exit_code
	$BIN_ECHO "Checking system image control sum ..."	
	local SUM_ORG=$($BIN_GREP $($BIN_BASENAME $IMAGE_REMOTE_NAME) $SUMS_LOCAL_NAME | $BIN_CUT -d " " -f 1)
	check_exit_code
	local SUM_FILE=$($BIN_MD5SUM $IMAGE_LOCAL_NAME | $BIN_CUT -d " " -f 1)
	check_exit_code
	if [ "$SUM_ORG" == "" ]; then
		$BIN_ECHO "Can't get original control sum!"
		exit 1
	elif [ "$SUM_FILE" == "" ]; then
		$BIN_ECHO "Can't calculate system image control sum!"
		exit 1
	elif [ "$SUM_ORG" != "$SUM_FILE" ]; then
		$BIN_ECHO "Downloaded system image is damaged!"
		exit 1
	else
		$BIN_ECHO "System image is downloaded and checksum is correct."
	fi
	run_script after_image_downloaded
}

installer_prepare() {
	$BIN_ECHO "Preparing packages installer in $POST_INSTALLER ..."
	$BIN_ECHO -e "#!/bin/sh"\
			"\n# Script auto-generated by $0"\
			"\n. /etc/diag.sh"\
			"\nget_status_led"\
			"\nset_state preinit"\
			"\nif [ -d /tmp/overlay-disabled ]; then"\
			"\n\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Removing overlay-rootfs checksum and force reboot\""\
			"\n\t$BIN_RM -f /tmp/overlay-disabled/.extroot.md5sum"\
			"\n\t$BIN_RM -f /tmp/overlay-disabled/etc/extroot.md5sum"\
			"\nelif [ -d /tmp/whole_root-disabled ]; then"\
			"\n\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Removing whole-rootfs checksum and force reboot\""\
			"\n\t$BIN_RM -f /tmp/whole_root-disabled/.extroot.md5sum"\
			"\n\t$BIN_RM -f /tmp/whole_root-disabled/etc/extroot.md5sum"\
			"\nelse"\
			"\n\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Start instalation of packages\"">$POST_INSTALLER
	check_exit_code
	if [ "$OFFLINE_POST_INSTALL" != "" ]; then
		$BIN_ECHO -e "\t$BIN_CAT /etc/opkg.conf | $BIN_AWK 'BEGIN{print \"src/gz local file:/$INSTALL_PATH\"}!/^src/{print \$0}' >/etc/opkg.conf">>$POST_INSTALLER
		check_exit_code
	else
		$BIN_ECHO -e "\tuntil $BIN_PING -q -W 30 -c 1 8.8.8.8 &>/dev/null; do"\
				"\t\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Wait for internet connection\""\
				"\n\tdone">>$POST_INSTALLER
		check_exit_code
	fi
	if [ "$RUN_SCRIPT" != "" ] && [ -x $RUN_SCRIPT ]; then
		$BIN_ECHO -e "\t$RUN_SCRIPT before_opkg_update | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT">>$POST_INSTALLER
		check_exit_code
	fi
	$BIN_ECHO -e "\t$BIN_OPKG update | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT">>$POST_INSTALLER
	if [ "$RUN_SCRIPT" != "" ] && [ -x $RUN_SCRIPT ]; then
		$BIN_ECHO -e "\t$RUN_SCRIPT before_opkg_install | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT">>$POST_INSTALLER
		check_exit_code
	fi
	$BIN_ECHO -e "\tlocal PACKAGES=\"$PACKAGES\""\
			"\n\tlocal PACKAGE"\
			"\n\tlocal SCRIPT"\
			"\n\tfor PACKAGE in \$PACKAGES; do"\
			"\n\t\t$BIN_OPKG install \$PACKAGE | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT"\
			"\n\t\tfor SCRIPT in \$($BIN_OPKG files \$PACKAGE | $BIN_GREP /etc/init.d/); do"\
			"\n\t\t\tif [ -x \$SCRIPT ]; then"\
			"\n\t\t\t\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Executing \$SCRIPT enable for package \$PACKAGE\""\
			"\n\t\t\t\t\$SCRIPT enable | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT"\
			"\n\t\t\tfi"\
			"\n\t\tdone"\
			"\n\tdone">>$POST_INSTALLER
	check_exit_code
	if [ "$RUN_SCRIPT" != "" ] && [ -x $RUN_SCRIPT ]; then
		$BIN_ECHO -e "\t$RUN_SCRIPT after_opkg_install | $BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT">>$POST_INSTALLER
		check_exit_code
	fi
	if [ "$BACKUP_ENABLE" != "" ]; then
		$BIN_ECHO -e "\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Restoring configuration backup from $BACKUP_FILE\""\
				"\n\t$BIN_SYSUPGRADE --restore-backup $BACKUP_FILE">>$POST_INSTALLER
		check_exit_code
	fi
	$BIN_ECHO -e "\t$BIN_LOGGER -p user.notice -t $POST_INSTALL_SCRIPT \"Stop installation of packages, cleaning and force reboot\""\
			"\n\t$BIN_RM $POST_INSTALL_REMOVE"\
			"\n\t$BIN_RM -f $INSTALLER_KEEP_FILE"\
			"\n\t$BIN_AWK -v installer=\"$POST_INSTALLER\" '\$0!~installer' $RC_LOCAL>$RC_LOCAL.tmp"\
			"\n\t$BIN_MV -f $RC_LOCAL.tmp $RC_LOCAL"\
			"\n\t$BIN_RM -f $POST_INSTALLER"\
			"\nfi"\
			"\n$BIN_LOGREAD >>$POST_INSTALLER_LOG"\
			"\n$BIN_SYNC"\
			"\n$BIN_REBOOT -f"\
			"\n# Done.">>$POST_INSTALLER
	check_exit_code
	$BIN_CHMOD 777 $POST_INSTALLER
	check_exit_code
	add_to_keep_file $POST_INSTALLER
	[ "$RUN_SCRIPT" != "" ] && [ -x $RUN_SCRIPT ] && add_to_keep_file $RUN_SCRIPT
	$BIN_ECHO "Setting autorun packages installer on next boot in $RC_LOCAL ..."
	add_to_keep_file $RC_LOCAL
	$BIN_ECHO -e "[ -x $POST_INSTALLER ] && $POST_INSTALLER\n$($BIN_CAT $RC_LOCAL)">$RC_LOCAL
	check_exit_code
	add_to_post_installer_log "Packages installer prepared"
	$BIN_ECHO "Packages installer prepared."
}

sysupgrade_execute() {
	$BIN_ECHO "Upgrading system from image $INSTALL_PATH/$IMAGE_FILENAME ..."
	add_to_keep_file $0
	add_to_post_installer_log "Running system upgrade"
	cd $INSTALL_PATH
	$BIN_SYSUPGRADE $IMAGE_FILENAME
}

# Main routine
initialize $@
[ "$CMD" == "backup" ] && config_backup && exit
[ "$CMD" == "sysupgrade" ] && caution_alert
update_repository
check_installed
check_dependency
([ "$CMD" == "install" ] || [ "$CMD" == "sysupgrade" ]) && config_backup
[ "$CMD" == "install" ] && packages_disable && packages_install
([ "$CMD" == "download" ] || ([ "$CMD" == "sysupgrade" ] && [ "$OFFLINE_POST_INSTALL" != "" ])) && packages_download
[ "$CMD" == "install" ] && config_restore && packages_enable
([ "$CMD" == "download" ] || [ "$CMD" == "sysupgrade" ]) && image_download
[ "$CMD" == "sysupgrade" ] && installer_prepare && packages_disable && sysupgrade_execute
$BIN_ECHO "Done."
# Done.
