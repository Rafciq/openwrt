#!/bin/sh
# Auto-generate vnstat portal.
# Script version 1.00 Rafal Drzymala 2013
#
# Changelog
#	1.00	RD	First stable code
#	1.01	RD	Interface nick added
#
# Destination /bin/vnstati_make.sh
#
VNSTAT_DB=$(awk '{if($1=="DatabaseDir") print substr($2,2,length($2)-2)}' /etc/vnstat.conf)	# db location
VNSTAT_BIN=$(which vnstat)  						# which vnstati
VNSTATI_WWW=/www/vnstat								# vnstati www dir
VNSTATI_OUT=/tmp/vnstat		  						# output images and HTML to here
VNSTATI_BIN=$(which vnstati)  						# which vnstati
VNSTATI_HTML=${VNSTATI_OUT}/index.html				# output HTML file
VNSTATI_CMD="--transparent --noheader --style 1"	# vnstati additional commands
VNSTATI_OUTS="vs d"   								# what images to generate
#
# h		hours
# d		days
# m		months
# t		top10
# s		summary
# hs	horizontal summary with hours
# vs	vertical summary with hours
# 
[ -d ${VNSTATI_OUT} ] || mkdir -p ${VNSTATI_OUT}
[ -L ${VNSTATI_WWW} ] && [ $(ls -l ${VNSTATI_WWW} | awk '{print $11}') == ${VNSTATI_OUT} ] || rm ${VNSTATI_WWW}
[ -L ${VNSTATI_WWW} ] || ln -s ${VNSTATI_OUT} ${VNSTATI_WWW}
echo "<!DOCTYPE html>">${VNSTATI_HTML}
echo "<HTML>">>${VNSTATI_HTML}
echo "<META HTTP-EQUIV=\"refresh\" CONTENT=\"300\">">>${VNSTATI_HTML}
echo "<META GENERATOR=\"$($VNSTATI_BIN --version)\">">>${VNSTATI_HTML}
echo "<HEAD>">>${VNSTATI_HTML}
echo "<TITLE>vnStat - $(uci get system.@system[0].hostname)</TITLE>">>${VNSTATI_HTML}
echo "</HEAD>">>${VNSTATI_HTML}
echo "<BODY BGCOLOR=\"#F0F0F0\">">>${VNSTATI_HTML}
echo "<FONT FACE=\"Tahoma\">">>${VNSTATI_HTML}
interfaces="$(ls -1 $VNSTAT_DB)"
outputs_count="$(echo \"$VNSTATI_OUTS\"|wc -w)"
if [ -z "$interfaces" ]; then
	echo "<H1>No database found ($VNSTAT_DB), nothing to do.</H1>">>${VNSTATI_HTML}
else
    for interface in $interfaces; do
		iface_nick=$(${VNSTAT_BIN} -i $interface --dumpdb | awk -F ";" '$1=="nick" {print $2}')
		[ "$iface_nick" == "" ] && iface_nick=$interface
		iface_jump="$iface_jump <A HREF=\"#$interface\">$iface_nick</A>"
    done
	echo "<TABLE BORDER=\"0\" WIDTH=\"100%\">">>${VNSTATI_HTML}
    for interface in $interfaces; do
		iface_nick=$(${VNSTAT_BIN} -i $interface --dumpdb | awk -F ";" '$1=="nick" {print $2}')
		if [ "$iface_nick" == "" ]; then
			iface_nick=$interface 
		else
			[ "$iface_nick" != "$interface" ] && iface_nick="$iface_nick ($interface)"
		fi
		echo "<TR>">>${VNSTATI_HTML}
		echo "<TH COLSPAN=\"$outputs_count\" ALIGN=\"center\" BGCOLOR=\"#DDDDDD\">">>${VNSTATI_HTML}
		echo "<A NAME=\"$interface\">">>${VNSTATI_HTML}
		echo "<DIV>Interface <STRONG>$iface_nick</STRONG></DIV>">>${VNSTATI_HTML}
		echo "</A>">>${VNSTATI_HTML}
		echo "</TH>">>${VNSTATI_HTML}
		echo "</TR>">>${VNSTATI_HTML}
		echo "<TR ALIGN=\"center\" VALIGN=\"top\">">>${VNSTATI_HTML}
        for output in $VNSTATI_OUTS; do
			echo "<TD>">>${VNSTATI_HTML}
			case  $output in
                h) image_type="Hourly";;
                d) image_type="Daily";;
                m) image_type="Monthly";;
                t) image_type="Top 10";;
                s|hs|vs) image_type="Summary";;
                *) image_type="Unknown $output";;
			esac 		
			echo "<DIV>$image_type</DIV>">>${VNSTATI_HTML}
			image=vnstat_${interface}_${output}.png
            $VNSTATI_BIN ${VNSTATI_CMD} --dbdir ${VNSTAT_DB} --iface $interface --output ${VNSTATI_OUT}/${image} -${output} 
			echo "<IMG SRC=\"$image\" ALT=\"$interface $image_type\"/>">>${VNSTATI_HTML}
			echo "</TD>">>${VNSTATI_HTML}
        done
		echo "</TR>">>${VNSTATI_HTML}
		echo "<TR>">>${VNSTATI_HTML}
		echo "<TD COLSPAN=\"$outputs_count\" ALIGN=\"center\" BGCOLOR=\"#E9E9E9\">">>${VNSTATI_HTML}
		echo "<DIV>Jump to:$iface_jump</DIV>">>${VNSTATI_HTML}
		echo "</TD>">>${VNSTATI_HTML}
		echo "</TR>">>${VNSTATI_HTML}
		echo "<TR><TD><P><BR></P></TD></TR>">>${VNSTATI_HTML}
    done
	echo "</TABLE>">>${VNSTATI_HTML}
fi
echo "</FONT>">>${VNSTATI_HTML}
echo "</BODY>">>${VNSTATI_HTML}
echo "</HTML>">>${VNSTATI_HTML}
exit 0
# Done