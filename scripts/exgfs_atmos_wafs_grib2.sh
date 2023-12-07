#!/bin/sh
######################################################################
#  UTILITY SCRIPT NAME :  exgfs_atmos_wafs_grib2.sh
#         DATE WRITTEN :  07/15/2009
#
#  Abstract:  This utility script produces the WAFS GRIB2. The output 
#             GRIB files are posted on NCEP ftp server and the grib2 files
#             are pushed via dbnet to TOC to WAFS (ICSC).  
#             This is a joint project of WAFC London and WAFC Washington.
#
#             We are processing WAFS grib2 for fcsthrs from 06 - 36 
#             with 3-hour time increment.
#
# History:  08/20/2014
#              - ingest master file in grib2 (or grib1 if grib2 fails)
#              - output of icng tcld cat cb are in grib2
#           02/21/2020
#              - Prepare unblended icing severity and GTG tubulence
#                for blending at 0.25 degree
#           02/22/2022
#              - Add grib2 data requested by FAA
#              - Stop generating grib1 data for WAFS
#####################################################################
echo "-----------------------------------------------------"
echo "JGFS_ATMOS_WAFS_GRIB2 at 00Z/06Z/12Z/18Z GFS postprocessing"
echo "-----------------------------------------------------"
echo "History: AUGUST  2009 - First implementation of this new script."
echo "Oct 2021 - Remove jlogfile"
echo "Feb 2022 - Add FAA data, stop grib1 data"
echo " "
#####################################################################

set -x

fcsthrs=$1

DATA=$DATA/$fcsthrs
mkdir -p $DATA
cd $DATA

##########################################################
# Wait for the availability of the gfs master pgrib file
##########################################################
# file name and forecast hour of GFS model data in Grib2 are 3 digits
export fcsthrs000="$(printf "%03d" $(( 10#$fcsthrs )) )"

# 2D data
master2=$COMIN/${RUN}.${cycle}.master.grb2f${fcsthrs000}
master2i=$COMIN/${RUN}.${cycle}.master.grb2if${fcsthrs000}
# 3D data
wafs2=$COMIN/${RUN}.${cycle}.wafs.grb2f${fcsthrs000}
wafs2i=$COMIN/${RUN}.${cycle}.wafs.grb2f${fcsthrs000}.idx
# 3D data (on ICAO standard level)
icao2=$COMIN/${RUN}.${cycle}.wafs_icao.grb2f${fcsthrs000}
icao2i=$COMIN/${RUN}.${cycle}.wafs_icao.grb2f${fcsthrs000}.idx

icnt=1
while [ $icnt -lt 1000 ]
do
    if [[ -s $master2i && -s $wafs2i ]] ; then
      break
    fi

    sleep 10
    icnt=$((icnt + 1))
    if [ $icnt -ge 180 ] ;    then
        msg="ABORTING after 30 min of waiting for the gfs master and wafs file!"
        err_exit $msg
    fi
done

########################################
echo "HAS BEGUN!"
########################################

echo " ------------------------------------------"
echo " BEGIN MAKING GFS WAFS GRIB2 PRODUCTS"
echo " ------------------------------------------"

set +x
echo " "
echo "#####################################"
echo "      Process GRIB WAFS PRODUCTS     "
echo " FORECAST HOURS 06 - 36."
echo "#####################################"
echo " "
set -x


if [ $fcsthrs -le 36 -a $fcsthrs -gt 0 ] ; then
    wafs_timewindow=yes
else
    wafs_timewindow=no
fi

#---------------------------
# 1) Grib2 data for FAA
#---------------------------
$WGRIB2 $master2 | grep -F -f $FIXgfs/faa_gfsmaster.grb2.list | $WGRIB2 -i $master2 -grib tmpfile_gfsf${fcsthrs}
# F006 master file has two records of 0-6 hour APCP and ACPCP each, keep only one
# FAA APCP ACPCP: included every 6 forecast hour (0, 48], every 12 forest hour [48, 72] (controlled by $FIXgfs/faa_gfsmaster.grb2.list)
if [ $fcsthrs -eq 6 ] ; then
    $WGRIB2 tmpfile_gfsf${fcsthrs} -not "(APCP|ACPCP)" -grib tmp.grb2
    $WGRIB2 tmpfile_gfsf${fcsthrs} -match APCP -append -grib tmp.grb2 -quit
    $WGRIB2 tmpfile_gfsf${fcsthrs} -match ACPCP -append -grib tmp.grb2 -quit
    mv tmp.grb2 tmpfile_gfsf${fcsthrs}
fi
# U V will have the same grid message number by using -ncep_uv.
# U V will have the different grid message number without -ncep_uv.
$WGRIB2 tmpfile_gfsf${fcsthrs} \
                      -set master_table 6 \
                      -new_grid_winds earth -set_grib_type jpeg \
                      -new_grid_interpolation bilinear -if ":(UGRD|VGRD):max wind" -new_grid_interpolation neighbor -fi \
                      -new_grid latlon 0:288:1.25 90:145:-1.25 gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2
$WGRIB2 -s gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2 > gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2.idx

# For FAA, add WMO header. The header is different from WAFS
export pgm=$TOCGRIB2
. prep_step
startmsg
export FORT11=gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2
export FORT31=" "
export FORT51=grib2.t${cyc}z.awf_grbf${fcsthrs}.45
$TOCGRIB2 <  $FIXgfs/grib2_gfs_awff${fcsthrs}.45 >> $pgmout 2> errfile
err=$?;export err ;err_chk
echo " error from tocgrib=",$err

if [ $wafs_timewindow = 'yes' ] ; then
#---------------------------
# 2) traditional WAFS fields
#---------------------------
    if [ "$ICAO2023" = 'yes' ] ; then
	# 3D data from $wafs2, on exact model pressure levels
	$WGRIB2 $wafs2 | grep -F -f $FIXgfs/wafs_gfsmaster.grb2.list | $WGRIB2 -i $wafs2 -grib tmpfile_gfsf${fcsthrs}
	# 2D data from $master2
	tail -5 $FIXgfs/wafs_gfsmaster.grb2.list > wafs_gfsmaster.grb2.list.2D
	$WGRIB2 $master2 | grep -F -f wafs_gfsmaster.grb2.list.2D | $WGRIB2 -i $master2 -grib tmpfile_gfsf${fcsthrs}.2D
	# Complete list of WAFS data
	cat tmpfile_gfsf${fcsthrs}.2D >> tmpfile_gfsf${fcsthrs}
	# WMO header
	cp $FIXgfs/grib2_gfs_wafsf${fcsthrs}.45 wafs_wmo_header45
    else
	$WGRIB2 $master2 | grep -F -f $FIXgfs/legend/wafs_gfsmaster.grb2.list | $WGRIB2 -i $master2 -grib tmpfile_gfsf${fcsthrs}
	# WMO header
	cp $FIXgfs/legend/grib2_gfs_wafsf${fcsthrs}.45 wafs_wmo_header45
    fi
    # U V will have the same grid message number by using -ncep_uv.
    # U V will have the different grid message number without -ncep_uv.
    $WGRIB2 tmpfile_gfsf${fcsthrs} \
            -set master_table 6 \
            -new_grid_winds earth -set_grib_type jpeg \
            -new_grid_interpolation bilinear -if ":(UGRD|VGRD):max wind" -new_grid_interpolation neighbor -fi \
            -new_grid latlon 0:288:1.25 90:145:-1.25 gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2
    $WGRIB2 -s gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2 > gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2.idx

    # For WAFS, add WMO header. Processing WAFS GRIB2 grid 45 for ISCS and WIFS
    export pgm=$TOCGRIB2
    . prep_step
    startmsg
    export FORT11=gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2
    export FORT31=" "
    export FORT51=grib2.t${cyc}z.wafs_grbf${fcsthrs}.45
    $TOCGRIB2 < wafs_wmo_header45 >> $pgmout 2> errfile
    err=$?;export err ;err_chk
    echo " error from tocgrib=",$err

    if [ "$ICAO2023" = 'yes' ] ; then
	mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2 gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2
	mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2.idx gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2.idx
    else
#---------------------------
# 3) WAFS hazard dataset (cb, icing, turbulence), will be stoped in 2023
#---------------------------

	cp $PARMgfs/legend/wafs_awc_wafavn.grb2.cfg waf.cfg

	date

	# For high resolution maste file, run time of awc_wafavn is 20 seconds for 1440 x 721, 
	# 3 minutes for new 3072 x 1536 master file for each forecast.
	# To reduce the time, will extract the required fields from master file and wafs files,
	# then convert to 1440 x 721.
	$WGRIB2 -npts $master2 > master.npts
	npts=`head -n1 master.npts | cut -d'=' -f2`
	newgrid="latlon 0:1440:0.25 90:721:-0.25"
	if [ $npts -gt 1038240 ] ; then
	    regrid_options="bilinear $newgrid"
	else
	    regrid_options=""
	fi

	options='-set_bitmap 1 -set_grib_type same -new_grid_winds earth'
	# 2D inputs for WAFS from master file, reference to type(pdt_t) parameters sorc/wafs_awc_wafavn.fd/waf_grib2.f90
	criteria1=":PRES:surface:|:PRES:convective|:CPRAT:.*hour.{1}ave"
	$WGRIB2 $master2 | egrep "$criteria1" |  $WGRIB2 -i $master2 -grib master.fields
	criteria=":HGT:.* mb:|:TMP:.* mb:|:UGRD:.* mb:|VGRD:.* mb:|:ICIP:.* mb:"
	$WGRIB2 $icao2 | egrep "$criteria" |  $WGRIB2 -i $icao2 -grib wafs.fields
	cat master.fields wafs.fields > masterfilef${fcsthrs}.new
	rm master.fields wafs.fields
	$WGRIB2  masterfilef${fcsthrs}.new $options -set master_table 6 -new_grid_interpolation bilinear -new_grid latlon 0:1440:0.25 90:721:-0.25 masterfilef${fcsthrs}

	export pgm=wafs_awc_wafavn
	. prep_step

	startmsg
	$EXECgfs/$pgm -c waf.cfg -i masterfilef${fcsthrs} -o tmpfile_icaof${fcsthrs} icng cat cb  >> $pgmout  2> errfile
	export err=$?; err_chk

	# To avoid interpolation of missing value (-0.1 or -1.0, etc), use neighbor interpolation instead of bilinear interpolation
	$WGRIB2 tmpfile_icaof${fcsthrs} -set_grib_type same -new_grid_winds earth \
		-new_grid_interpolation bilinear -if ":CBHE:" -new_grid_interpolation neighbor -fi \
		-new_grid latlon 0:288:1.25 90:145:-1.25 tmpfile_icao_grb45f${fcsthrs}
	# after grid conversion by wgrib2, even with neighbor interpolation, values may still be mislead by noises, epescially 
	# the ref_value is not zero according to DST template 5.XX. Solution: rewrite and round those special meaning values
	export pgm=wafs_setmissing
	. prep_step
	$EXECgfs/wafs_setmissing tmpfile_icao_grb45f${fcsthrs} tmpfile_icao_grb45f${fcsthrs}.setmissing
	mv tmpfile_icao_grb45f${fcsthrs}.setmissing tmpfile_icao_grb45f${fcsthrs}

#---------------------------
# 4) combine hazard and traditional WAFS fields
#---------------------------
	cat gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2 tmpfile_icao_grb45f${fcsthrs} > gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2
	# Stop support grib1 data beginning from 2023
	#  $CNVGRIB -g21 gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2 gfs.t${cyc}z.wafs_grb45f${fcsthrs}
	$WGRIB2 -s gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2 > gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2.idx

	# Processing WAFS GRIB2 grid 45 (Icing, TB, CAT) for WIFS
	export pgm=$TOCGRIB2
	. prep_step
	startmsg
	export FORT11=gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2
	export FORT31=" "
	export FORT51=grib2.t${cyc}z.wafs_grb_wifsf${fcsthrs}.45
	$TOCGRIB2 <  $FIXgfs/legend/grib2_gfs_wafs_wifs_f${fcsthrs}.45 >> $pgmout 2> errfile
	err=$?;export err ;err_chk
	echo " error from tocgrib=",$err
    fi # ICAO2023
fi # wafs_timewindow

if [ $SENDCOM = "YES" ] ; then

    ##############################
    # Post Files to COM
    ##############################

    # FAA data
    mv gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2 $COMOUT/gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2
    mv gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2.idx $COMOUT/gfs.t${cyc}z.awf_grb45f${fcsthrs}.grib2.idx

    # WAFS data
    if [ $wafs_timewindow = 'yes' ] ; then
	if [ ! "$ICAO2023" = 'yes' ] ; then
	    mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2 $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2
	    mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2.idx $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2.idx
	    # Retiring grib1 data
	    # mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}  $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}
	fi
	mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2 $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2
	mv gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2.idx $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2.idx
    fi

    ##############################
    # Post Files to PCOM
    ##############################

    mv grib2.t${cyc}z.awf_grbf${fcsthrs}.45  $PCOM/grib2.t${cyc}z.awf_grbf${fcsthrs}.45

    if [ $wafs_timewindow = 'yes' ] ; then
	mv grib2.t${cyc}z.wafs_grbf${fcsthrs}.45  $PCOM/grib2.t${cyc}z.wafs_grbf${fcsthrs}.45
        if [ ! "$ICAO2023" = 'yes' ] ; then
	    mv grib2.t${cyc}z.wafs_grb_wifsf${fcsthrs}.45  $PCOM/grib2.t${cyc}z.wafs_grb_wifsf${fcsthrs}.45
	fi
    fi
fi

######################
# Distribute Data
######################

if [ $SENDDBN = "YES" ] ; then

#  
#    Distribute Data to WOC
#  
    if [ $wafs_timewindow = 'yes' ] ; then
        if [ ! "$ICAO2023" = 'yes' ] ; then
	    $DBNROOT/bin/dbn_alert MODEL GFS_WAFSA_GB2 $job $PCOM/grib2.t${cyc}z.wafs_grb_wifsf${fcsthrs}.45
	    $DBNROOT/bin/dbn_alert MODEL GFS_WAFSA_GB2 $job $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2
	    $DBNROOT/bin/dbn_alert MODEL GFS_WAFSA_GB2_WIDX $job $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.nouswafs.grib2.idx
	else
	    $DBNROOT/bin/dbn_alert MODEL GFS_WAFS_1P25_GB2 $job $COMOUT/gfs.t${cyc}z.wafs_grb45f${fcsthrs}.grib2
	fi
#
#       Distribute Data to TOC TO WIFS FTP SERVER (AWC)
#
	$DBNROOT/bin/dbn_alert NTC_LOW $NET $job $PCOM/grib2.t${cyc}z.wafs_grbf${fcsthrs}.45
    fi
#
#   Distribute data to FAA
#
    $DBNROOT/bin/dbn_alert NTC_LOW $NET $job $PCOM/grib2.t${cyc}z.awf_grbf${fcsthrs}.45


fi

################################################################################
# GOOD RUN
set +x
echo "**************JOB EXGFS_ATMOS_WAFS_GRIB2.SH COMPLETED NORMALLY ON THE IBM"
echo "**************JOB EXGFS_ATMOS_WAFS_GRIB2.SH COMPLETED NORMALLY ON THE IBM"
echo "**************JOB EXGFS_ATMOS_WAFS_GRIB2.SH COMPLETED NORMALLY ON THE IBM"
set -x
################################################################################

echo "HAS COMPLETED NORMALLY!"

exit 0

############## END OF SCRIPT #######################
