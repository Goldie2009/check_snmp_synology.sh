#!/bin/bash
#
# check_snmp_synology for nagios/icinga version 3.0
# 18.10.2016 Gérard Gold, Germany
# 
#---------------------------------------------------
# this plugin checks the health of your Synology NAS
# - System status (Power, Fans, ...)
# - Disks status 
# - RAID status and Storage percentage of use
# - DSM update status
# - Temperature Warning and Critical
# - UPS information
# 
# Tested with DSM 6.0
# 
# inspired by
#
# check_snmp_synology for nagios version 2.2 
# 16.04.2015  Nicolas Ordonez, Switzerland
#---------------------------------------------------
# Based on http://ukdl.synology.com/download/Document/MIBGuide/Synology_DiskStation_MIB_Guide.pdf 
#---------------------------------------------------
# actual number disk limit = 52 disks per Synology
#---------------------------------------------------
 
#defaults
SNMPWALK=$(which snmpwalk)
SNMPGET=$(which snmpget)
SNMPVersion="3"
SNMPV2Community="public"
SNMPTimeout="10"
option="status"
warning="50"
critical="60"
hostname=""
healthWarningStatus=0
exitcode=0
verbose="no"
ups="no"

#output messages
teaserOutput=""
verboseOutput=""
perfdata="| "

#OID declarations
OID_syno="1.3.6.1.4.1.6574"
OID_model="1.3.6.1.4.1.6574.1.5.1.0"
OID_serialNumber="1.3.6.1.4.1.6574.1.5.2.0"
OID_DSMVersion="1.3.6.1.4.1.6574.1.5.3.0"
OID_DSMUpgradeAvailable="1.3.6.1.4.1.6574.1.5.4.0"
OID_systemStatus="1.3.6.1.4.1.6574.1.1.0"
OID_temperature="1.3.6.1.4.1.6574.1.2.0"
OID_powerStatus="1.3.6.1.4.1.6574.1.3.0"
OID_systemFanStatus="1.3.6.1.4.1.6574.1.4.1.0"
OID_CPUFanStatus="1.3.6.1.4.1.6574.1.4.2.0"
OID_disk=""
OID_disk2=""
OID_diskID="1.3.6.1.4.1.6574.2.1.1.2"
OID_diskModel="1.3.6.1.4.1.6574.2.1.1.3"
OID_diskStatus="1.3.6.1.4.1.6574.2.1.1.5"
OID_diskTemp="1.3.6.1.4.1.6574.2.1.1.6"
OID_RAID=""
OID_RAIDName="1.3.6.1.4.1.6574.3.1.1.2"
OID_RAIDStatus="1.3.6.1.4.1.6574.3.1.1.3"
OID_Storage="1.3.6.1.2.1.25.2.3.1"
OID_StorageDesc="1.3.6.1.2.1.25.2.3.1.3"
OID_StorageAllocationUnits="1.3.6.1.2.1.25.2.3.1.4"
OID_StorageSize="1.3.6.1.2.1.25.2.3.1.5"
OID_StorageSizeUsed="1.3.6.1.2.1.25.2.3.1.6"
OID_UpsModel="1.3.6.1.4.1.6574.4.1.1.0"
OID_UpsSN="1.3.6.1.4.1.6574.4.1.3.0"
OID_UpsStatus="1.3.6.1.4.1.6574.4.2.1.0"
OID_UpsLoad="1.3.6.1.4.1.6574.4.2.12.1.0"
OID_UpsBatteryCharge="1.3.6.1.4.1.6574.4.3.1.1.0"
OID_UpsBatteryChargeWarning="1.3.6.1.4.1.6574.4.3.1.4.0"

#manual
fManual()
{
	echo "usage: ./check_snmp_synology [SNMP_Version] -h [hostname] -u [user] -p [pass] -o [option] -w [warning] -c [critical]"
	echo "options:"
	echo "            -h [hostname]         Hostname of your Synology"
    echo "			  -u [snmp username]   	Username for SNMPv3"
	echo "            -p [snmp password]   	Password for SNMPv3"
	echo ""
	echo "            -2 [community name]	Use SNMPv2 (no need user/password) & define community name (ex: public)"
	echo "            -o [option]			wanted information disk|raid|status|temperature|update|ups (default $detail)"
	echo ""            
	echo "            -w [warning]			Warning storage usage (%) or temperature (°C)(default $warning)"
	echo "            -c [critical]			Critical storage usage (%) or temperature (°C) (default $critical)"
	echo ""
	echo "            -U   					Show informations about the connected UPS (only information, no control)"
    echo "            -v   					Verbose - print all informations about your Synology"
	echo ""
	echo "examples:	  ./check_snmp_synology -h nas.intranet -u admin -p 1234 -o update"		
	echo "	     	  ./check_snmp_synology -d nas.intranet -u admin -p 1234 -o status -v"	
	echo "		      ./check_snmp_synology -h nas.intranet -2 public -d temperature -w 50 -c 60"		
	exit 3
}

#manual needed
if [ "$1" == "--help" ]; then
    fManual; exit 0
fi

#get arguments
while getopts 2:o:w:c:u:p:h:Uv OPTNAME; 
do
	case "$OPTNAME" in
	h)	hostname="$OPTARG";;
	u)	SNMPUser="$OPTARG";;
	p)	SNMPPassword="$OPTARG";;
	2)	SNMPVersion="2" SNMPV2Community="$OPTARG";;
	o)	option="$OPTARG";;
	w)	warning="$OPTARG";;
	c)  critical="$OPTARG";;
	v)	verbose="yes";;
	U)	ups="yes";;
	*)	fManual;;
	esac
done

if [ "$option" != "disk" ] && [ "$option" != "raid" ] && [ "$option" != "status" ] && [ "$option" != "temperature" ] && [ "$option" != "update" ] && [ "$option" != "ups" ] ; then
	fManual; exit 0
fi

#check warning and critical values
if [ "$warning" -gt "$critical" ] ; then
    echo "Critical value must be higher than warning value"
    if( "$option" == "temperature" ) ; then
		echo "Warning temperature: $warning°C"
		echo "Critical temperature: $critical°C"
		echo ""
	fi
	if( "$option" == "disk" ) ; then
	    echo "Warning: $warning"
		echo "Critical: $critical"
		echo ""
    fi
	echo "For more information:  ./${0##*/} --help" 
    exit 1 
fi

#connect

if [ "$hostname" = "" ] || ([ "$SNMPVersion" = "3" ] && [ "$SNMPUser" = "" ]) || ([ "$SNMPVersion" = "3" ] && [ "$SNMPPassword" = "" ]) ; then
	fManual
else
if [ "$SNMPVersion" = "2" ] ; then
	SNMPArgs=" -OQne -v 2c -c $SNMPV2Community -t $SNMPTimeout"
else
	SNMPArgs=" -OQne -v 3 -u $SNMPUser -A $SNMPPassword -l authNoPriv -a MD5 -t $SNMPTimeout"
if [ ${#SNMPPassword} -lt "8" ] ; then
	echo "snmpwalk:  (The supplied password length is too short.)"
	exit 1
fi
fi
tmpRequest=`$SNMPWALK $SNMPArgs $hostname $OID_syno 2> /dev/null`
if [ "$?" != "0" ] ; then
	echo "CRITICAL - Problem with SNMP request, check user/password/host"
	exit 2
fi 
nbDisk=$(echo "$tmpRequest" | grep $OID_diskID | wc -l)
nbRAID=$(echo "$tmpRequest" | grep $OID_RAIDName | wc -l)

for i in `seq 1 $nbDisk`;
do
	if [ $i -lt 25 ] ; then
		OID_disk="$OID_disk $OID_diskID.$(($i-1)) $OID_diskModel.$(($i-1)) $OID_diskStatus.$(($i-1)) $OID_diskTemp.$(($i-1))" 
	else
		OID_disk2="$OID_disk2 $OID_diskID.$(($i-1)) $OID_diskModel.$(($i-1)) $OID_diskStatus.$(($i-1)) $OID_diskTemp.$(($i-1))"
	fi   
done

for i in `seq 1 $nbRAID`;
do
  OID_RAID="$OID_RAID $OID_RAIDName.$(($i-1)) $OID_RAIDStatus.$(($i-1))" 
done

syno=`$SNMPGET $SNMPArgs $hostname $OID_model $OID_serialNumber $OID_DSMVersion $OID_systemStatus $OID_temperature $OID_powerStatus $OID_systemFanStatus $OID_CPUFanStatus $OID_disk $OID_RAID $OID_DSMUpgradeAvailable $OID_UpsModel $OID_UpsSN $OID_UpsStatus $OID_UpsLoad $OID_UpsBatteryCharge $OID_UpsBatteryChargeWarning 2> /dev/null`

if [ "$OID_disk2" != "" ]; then
	syno2=`$SNMPGET $SNMPArgs $hostname $OID_disk2 2> /dev/null`
	syno=$(echo "$syno";echo "$syno2";)
fi

model=$(echo "$syno" | grep $OID_model | cut -d "=" -f2)
serialNumber=$(echo "$syno" | grep $OID_serialNumber | cut -d "=" -f2)
DSMVersion=$(echo "$syno" | grep $OID_DSMVersion | cut -d "=" -f2)
RAIDName=$(echo "$syno" | grep $OID_RAIDName | cut -d "=" -f2)
RAIDStatus=$(echo "$syno" | grep $OID_RAIDStatus | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
syno_diskspace=`$SNMPWALK $SNMPArgs $hostname $OID_Storage 2> /dev/null`
temperature=$(echo "$syno" | grep $OID_temperature | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
teaserOutput="Synology $model (s/n:$serialNumber, $DSMVersion), "

verboseOutput+="Synology model:		$model\n" 
verboseOutput+="Synology s/n:			$serialNumber\n"
verboseOutput+="DSM Version:			$DSMVersion\n"
verboseOutput+="System temperature:		 	$temperature°C\n"
verboseOutput+="Number of disks:      $nbDisk\n"
verboseOutput+="Number of RAID volumes:   $nbRAID\n"
for i in `seq 1 $nbRAID`;
	do
		verboseOutput+=" ${RAIDName[$i]} status:${RAIDStatus[$i]} ${storagePercentUsedString[$i]}\n"
	done

#disk
if [ "$option" == "disk" ]; then
	for i in `seq 1 $nbDisk`;
		do
			diskID[$i]=$(echo "$syno" | grep "$OID_diskID.$(($i-1)) " | cut -d "=" -f2)
			diskModel[$i]=$(echo "$syno" | grep "$OID_diskModel.$(($i-1)) " | cut -d "=" -f2 )
			diskStatus[$i]=$(echo "$syno" | grep "$OID_diskStatus.$(($i-1)) " | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')

			case ${diskStatus[$i]} in
				"1")	diskStatus[$i]="Normal";		;;
				"2")	diskStatus[$i]="Initialized";		;;
				"3")	diskStatus[$i]="NotInitialized";	;;
				"4")	diskStatus[$i]="SystemPartitionFailed";	exitcode=2; verboseOutput+=" problem with ${diskID[$i]} (model:${diskModel[$i]}) status:${diskStatus[$i]} temperature:${diskTemp[$i]} °C";;
				"5")	diskStatus[$i]="Crashed";		exitcode=2;	verboseOutput+=" problem with ${diskID[$i]} (model:${diskModel[$i]}) status:${diskStatus[$i]} temperature:${diskTemp[$i]} °C";;
			esac
		done 
        if [ "$exitcode" == 2 ] ; then
        	teaserOutput+=" Disk is critical!"
        fi
        if [ "$exitcode" == 1 ] ; then
        	teaserOutput+=" Disk is warning!"
        fi
fi

# raid
if [ "$option" == "raid" ] ; then
	#Check all RAID volume status
    for i in `seq 1 $nbRAID`;
    do
		RAIDName[$i]=$(echo "$syno" | grep $OID_RAIDName.$(($i-1)) | cut -d "=" -f2)
		RAIDStatus[$i]=$(echo "$syno" | grep $OID_RAIDStatus.$(($i-1)) | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
		storageName[$i]=$(echo "${RAIDName[$i]}" | sed -e 's/[[:blank:]]//g' | sed -e 's/\"//g' | sed 's/.*/\L&/')
		storageID[$i]=$(echo "$syno_diskspace" | grep ${storageName[$i]} | cut -d "=" -f1 | rev | cut -d "." -f1 | rev)
		if [ "${storageID[$i]}" != "" ] ; then
			storageSize[$i]=$(echo "$syno_diskspace" | grep "$OID_StorageSize.${storageID[$i]}" | cut -d "=" -f2 )
			storageSizeUsed[$i]=$(echo "$syno_diskspace" | grep "$OID_StorageSizeUsed.${storageID[$i]}" | cut -d "=" -f2 )
			storageAllocationUnits[$i]=$(echo "$syno_diskspace" | grep "$OID_StorageAllocationUnits.${storageID[$i]}" | cut -d "=" -f2 )
			storagePercentUsed[$i]=$((${storageSizeUsed[$i]} * 100 / ${storageSize[$i]}))
			storagePercentUsedString[$i]="${storagePercentUsed[$i]}% used"
			if [ "${storagePercentUsed[$i]}" -gt "$warning" ] ; then
				if [ "${storagePercentUsed[$i]}" -gt "$critical" ] ; then
					exitcode=2;
					storagePercentUsedString[$i]="${storagePercentUsedString[$i]} CRITICAL , "
				else
					exitcode=1;
					storagePercentUsedString[$i]="${storagePercentUsedString[$i]} WARNING , "
				fi
			fi
            teaserOutput+="${RAIDName[$i]}: ${storagePercentUsedString[$i]}, "
            perfdata+="'${RAIDName[i]}'=${storagePercentUsed[$i]};$warning;$critical;;"
		fi
        case ${RAIDStatus[$i]} in
			"1")	RAIDStatus[$i]="Normal";				raidstatuscode=0;		teaserOutput+="RAID status ${RAIDName[$i]}: Normal, ";;
			"2")	RAIDStatus[$i]="Repairing";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"3")	RAIDStatus[$i]="Migrating";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"4")	RAIDStatus[$i]="Expanding";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"5")	RAIDStatus[$i]="Deleting";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"6")	RAIDStatus[$i]="Creating";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"7")	RAIDStatus[$i]="RaidSyncing";			raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"8")	RAIDStatus[$i]="RaidParityChecking";	raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"9")	RAIDStatus[$i]="RaidAssembling";		raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"10")	RAIDStatus[$i]="Canceling";				raidstatuscode=1;		teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"11")	RAIDStatus[$i]="Degrade";				exitcode=2;				teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
			"12")	RAIDStatus[$i]="Crashed";				exitcode=2;				teaserOutput+="RAID status ${RAIDName[$i]}: ${RAIDStatus[$i]}, ";;
        esac
        if [ "$exitcode" != 2 ] && [ "raidstatuscode" == 1 ] ; then
        	exitcode=1
        fi
    done
    perfdata+="'RAID status'=$raidstatuscode;1;2;;"
fi

#temperature
if [ "$option" == "temperature" ] ; then
	if [ "$temperature" -gt "$warning" ] ; then
    	if [ "$temperature" -gt "$critical" ] ; then
        	verboseOutput+="System temperature: $temperature °C (Critical) \n"
	        exitcode=2
		else
			verboseOutput+="System temperature: $temperature °C (Warning) \n"
	        exitcode=1
		fi
    fi
	perfdata+="'System'=$temperature;$warning;$critical;;"
    for i in `seq 1 $nbDisk`;
	do
    	diskID[$i]=$(echo "$syno" | grep "$OID_diskID.$(($i-1)) " | cut -d "=" -f2)
		diskModel[$i]=$(echo "$syno" | grep "$OID_diskModel.$(($i-1)) " | cut -d "=" -f2 )
		diskTemp[$i]=$(echo "$syno" | grep "$OID_diskTemp.$(($i-1)) " | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [ "${diskTemp[$i]}" -gt "$warning" ] ; then
            if [ "${diskTemp[$i]}" -gt "$critical" ] ; then
               	diskTemp[$i]="${diskTemp[$i]} "
               	exitcode=2;
            	verboseOutput+="${diskID[$i]} temperature: ${diskTemp[$i]} °C (Critical)\n"
            else
            	diskTemp[$i]="${diskTemp[$i]} "
                if [ "$exitcode" != 2 ] ; then
                	exitcode=1;
                fi
                verboseOutput+="${diskID[$i]} temperature: ${diskTemp[$i]} °C (Warning)\n"
           	fi
        fi
		perfdata+=" '${diskID[$i]}'=${diskTemp[$i]};$warning;$critical;;"
	done
    if [ "$exitcode" == 2 ] ; then
       	teaserOutput+=" Temperature is critical!"
    fi
    if [ "$exitcode" == 1 ] ; then
       	teaserOutput+=" Temperature is warning!"
    fi
fi

#status
if [ "$option" == "status" ] ; then
	# get values
	systemStatus=$(echo "$syno" | grep $OID_systemStatus | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
    powerStatus=$(echo "$syno" | grep $OID_powerStatus | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
    systemFanStatus=$(echo "$syno" | grep $OID_systemFanStatus | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
    CPUFanStatus=$(echo "$syno" | grep $OID_CPUFanStatus | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
    # check system status
    if [ "$systemStatus" = "1" ] ; then
		verboseOutput+="System status: Normal \n"
    else
		exitcode=2
        teaserOutput+="System status: Failed "
        verboseOutput+="System status: Failed \n"
    fi
    # check power status
    if [ "$powerStatus" = "1" ] ; then
    	verboseOutput+="Power status: Normal "
    else
       	exitcode=2
        teaserOutput+="Power status: Failed "
        verboseOutput+="Power status: Failed\n"
    fi
    # check system fan status
    if [ "$systemFanStatus" = "1" ] ; then
        verboseOutput+="System fan status: Normal \n"
    else
        exitcode=2
        teaserOutput+="System fan status: Failed "
        verboseOutput+="System fan status: Failed \n"
    fi
    # check CPU fan status
    if [ "$CPUFanStatus" = "1" ] ; then
		verboseOutput+="CPU fan status: Normal \n"
    else
        exitcode=2
        teaserOutput+="CPU fan status: Failed "
        verboseOutput+="CPU fan status: Failed \n"
    fi
    if [ "$exitcode" = 0 ] ; then
    	teaserOutput+="System state normal. "
    fi
    perfdata+="'Status'=$exitcode;1;2;;"
fi

#update
if [ "$option" == "update" ] ; then
	DSMUpgradeAvailable=$(echo "$syno" | grep $OID_DSMUpgradeAvailable | cut -d "=" -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
    case $DSMUpgradeAvailable in
		"1")	DSMUpgradeAvailable="Available";	exitcode=1;		teaserOutput+="DSM update available";;
		"2")	DSMUpgradeAvailable="Unavailable";;
		"3")	DSMUpgradeAvailable="Connecting";;					
		"4")	DSMUpgradeAvailable="Disconnected";	exitcode=1;		teaserOutput+="DSM Update Disconnected";;
		"5")	DSMUpgradeAvailable="Others";		exitcode=1;		teaserOutput+="Check DSM Update";;
    esac
fi

#ups
if [ "$option" == "ups" ] ; then
	# Display UPS information
	upsModel=$(echo "$syno" | grep $OID_UpsModel | cut -d "=" -f2)
	upsSN=$(echo "$syno" | grep $OID_UpsSN | cut -d "=" -f2)
	upsStatus=$(echo "$syno" | grep $OID_UpsStatus | cut -d "=" -f2)
	upsLoad=$(echo "$syno" | grep $OID_UpsLoad | cut -d "=" -f2)
	upsBatteryCharge=$(echo "$syno" | grep $OID_UpsBatteryCharge | cut -d "=" -f2)
	upsBatteryChargeWarning=$(echo "$syno" | grep $OID_UpsBatteryChargeWarning | cut -d "=" -f2)
	verboseOutput+="UPS:\n"
	verboseOutput+="  Model:					$upsModel\n"
	verboseOutput+="  s/n:						$upsSN\n"
	verboseOutput+="  Status:					$upsStatus\n"
	verboseOutput+="  Load:						$upsLoad\n"
	verboseOutput+="  Battery charge:			$upsBatteryCharge\n"
	verboseOutput+="  Battery charge warning:	$upsBatteryChargeWarning\n"
fi

echo $teaserOutput
#verboseOutput
if [ "$verbose" == "yes" ] ; then
	echo $verboseOutput
fi
echo $perfdata
exit $exitcode
fi