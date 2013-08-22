#!/bin/sh
# Example script to customize process of install.sh script
# 
# You have to add runscript option to sysupgrade section in /etc/config/system file 
# For example:
#	config sysupgrade
#		. . .
#		option runscript '/bin/install_ext.sh'
#
# Destination /bin/install_ext.sh
#

after_image_downloaded() {
    echo "after-image-downloaded"
	# Insert your code here
}

before_opkg_update() {
    echo "before-opkg-update"
	# Insert your code here
}

before_opkg_install() {
    echo "before-opkg-install"
	# Insert your code here
}

after_opkg_install() {
    echo "after-opkg-install"
	# Insert your code here
}

# Main routine
while [ -n "$1" ]; do 
    if type $1 | grep -q ' function'; then
        $1
    else
        echo "Invalid argument $1"
    fi
    shift 
done
# Done.