#!/bin/sh


# usage:
# ./avalua_single.sh 7 pub_8 TAINTED_EXE > SINGLE_SOLUTION 2> SINGLE_ERR


# The following program is kludgy and hacky, a lot of essential
# information is encoded within the code itself, instead of on
# separate, configrable data.  However, the code tries to be safe...
# I check the output of every command after being called, and exit
# with a descriptive error if it fails.



IDENTITY="/home/`whoami`/.ssh/id_rsa"
EVIL="bush@localhost"
JAIL=/home/jail

LOCAL_SCRATCH=/tmp/graphie_local_scratch
REMOTE_SCRATCH=/tmp/graphie_remote_scratch

# see ../sorra/setrim.c
#SETRLIM="setrlim AS 150000000 160000000 CPU 1 2 NPROC 10 10 NOFILE 5 5 FSIZE 524288 524288"
SETRLIM="nurse AS 150000000 160000000 CPU 10 11 NPROC 10 10 NOFILE 10 10 FSIZE 5242880 5242880 --"




# TODO: make secure data copies to and from the jail WITHOUT ssh
# (e.g., directly into /home/jail, with appropriate group
# permissions).  We will gain about 2 seconds for each execution







############################
############################
##  BEGINNING OF PROGRAM  ##
############################
############################


# check number of arguments
if [ $# != "3" ]; then
	echo "usage:\n\t ./avalua_single dir {pub,priv}_n executable >SOL 2>SOLERR"
	exit 1
fi


TESTNAME=$2
TAINTED_EXE=$3


# check that we have enough data for this run
if [ ! -d $1 ]; then
	echo "ERROR: el directori $1 no existeix"
	exit 1
fi
if [ ! -f $1/${TESTNAME}_args ]; then
	echo "ERROR: args file $1/${TESTNAME}_args missing!"
	exit 1
fi
if [ ! -f $1/${TESTNAME}_out ]; then
	echo "ERROR: solution file $1/${TESTNAME}_out missing!"
	exit 1
fi
if [ ! -f $TAINTED_EXE ]; then
	echo "ERROR: executable file $TAINTED_EXE missing!"
	exit 1
fi


# check evil ssh connection
#NNN=`ssh -i $IDENTITY $EVIL "setrlim CPU 1 2 -- /bin/ls -a /etc 2>/dev/null | wc -l"`
#NRC=$?
#if [[ $NNN != "18" || $NRC != "0" ]]; then # HACKED MAGIC NUMBERS HERE!
#	echo "ERROR: evil returned number $NNN with exit code $NRC"
#	echo "ERROR: could not connect correctly to the evil server!"
#	exit 1
#fi


# build local scratch dir
if [ -e $LOCAL_SCRATCH ]; then
	rm -rf $LOCAL_SCRATCH
fi
if [ -e $LOCAL_SCRATCH ]; then
	echo "ERROR: could not clean local scratch dir \"$LOCAL_SCRATCH\""
	exit 1
fi
mkdir -p $LOCAL_SCRATCH
if [ ! -e $LOCAL_SCRATCH ]; then
	echo "ERROR: could not create local scratch dir \"$LOCAL_SCRATCH\""
	exit 1
fi

if [ ! -e $LOCAL_GSCRATCH ]; then
	echo "ERROR: can not run without a local gscratch dir"
	exit 1
fi

# build remote scratch dir
ssh -i $IDENTITY $EVIL "rm -rf $REMOTE_SCRATCH && mkdir -p $REMOTE_SCRATCH && chmod a+w $REMOTE_SCRATCH"
if [ ! $? -eq 0 ]; then
	echo "ERROR: could not create remote scratch dir \"$REMOTE_SCRATCH\""
	exit 1
fi


## copy relevant files to remote scratch dir
#scp -i $IDENTITY $TAINTED_EXE $1/${TESTNAME}_args ${EVIL}:${REMOTE_SCRATCH}
## TODO: copy data files also
#if [ ! $? -eq 0 ]; then
#	echo "ERROR: could not send data to remote scratch dir"
#	exit 1
#fi
cp $1/${TESTNAME}_args $TAINTED_EXE ${JAIL}${REMOTE_SCRATCH} 2>>/tmp/memme
if [ ! $? -eq 0 ]; then
	echo "ERROR: could not send data to remote scratch dir"
	exit 1
fi

# copy further data files (XXX: no sanity checking here yet!!!)
if [ -d $1/files_pub ]; then
	for i in $1/files_pub/*; do
		if [ -f $i ]; then
			cp $i ${JAIL}${REMOTE_SCRATCH} 2>>/tmp/memme
		fi
	done
fi
if [ -d $1/files_priv ]; then
	for i in $1/files_priv/*; do
		if [ -f $i ]; then
			cp $i ${JAIL}${REMOTE_SCRATCH}
		fi
	done
fi


TBNAME=`basename $TAINTED_EXE`
TBARGS=`cat $1/${TESTNAME}_args`


#######################
##  HERE BE DRAGONS  ##
#######################

# run the tainted executable on the scratch directory
ssh -i $IDENTITY $EVIL "cd $REMOTE_SCRATCH && PLIMIT_CONFIG_FILE=/usr/lib/ptropt.ptropt $SETRLIM ./$TBNAME $TBARGS >.o 2>.oe ; echo \$? >.or" 2> $LOCAL_SCRATCH/localoe
if [ ! $? -eq 0 ]; then
	echo "ERROR: something went worng! (exit code = $? )"
	echo "local error:"
	cat $LOCAL_SCRATCH/localoe
# TODO: interpret SEGFAULTS and ABORTS here!!!
	exit 1
fi
# TODO: interpret and display OUTOFMEMS, MAXFILES, TIMEOUTS here!!!
# TODO: display program exit code


# fastly copy the command output
cp ${JAIL}${REMOTE_SCRATCH}/.o $LOCAL_SCRATCH/oo && cp ${JAIL}${REMOTE_SCRATCH}/.oe $LOCAL_SCRATCH/oe && cp ${JAIL}${REMOTE_SCRATCH}/.or $LOCAL_SCRATCH/or

if [ ! $? -eq 0 ]; then
	echo "ERROR: something went *strangely* worng!"
	exit 1
fi

# misc output
UPR=`cat $LOCAL_SCRATCH/or`
if [ ! $UPR == "0" ]; then
	echo "ssh program returned $UPR"
	if [ -s $LOCAL_SCRATCH/localoe ]; then
		echo "LOCALOE:"
		cat $LOCAL_SCRATCH/localoe
	fi
fi

#echo "ho-hooo-ho problema $1"
#echo "ho-hooo-ho joc de proves $TESTNAME"

# compare correct output with the student's output
# TODO: problem-dependent canonicalization
if [ $1 == "6" ]; then
	#echo "problema sis"
	#echo "joc de proves $TESTNAME"
	#echo "WARNING: private correction not fully implemented!!!"
	# EXTREMELY HACKY MST-CORRECTION
	if echo $TESTNAME | grep -q pub; then
		#echo "joc públic: $TESTNAME"
		cat $LOCAL_SCRATCH/oo | ./canonprim.lua | sort -n > $LOCAL_SCRATCH/coo
		cmp --quiet $1/${TESTNAME}_out $LOCAL_SCRATCH/coo
		CMPR=$?
		#echo "cmp --quiet $1/${TESTNAME}_out $LOCAL_SCRATCH/coo"
		#echo "CMPR=$CMPR"
	else
		#echo "joc privat: $TESTNAME"
		./corregeix_prim `cat $1/${TESTNAME}_zol` < $LOCAL_SCRATCH/oo
		CMPR=$?
	fi
fi

if [ $1 == "7" ]; then
	#echo "problema set"
	#echo "joc de proves $TESTNAME"
	./corregeix_kruskal `cat $1/${TESTNAME}_zol` < $LOCAL_SCRATCH/oo 2>&1
	CMPR=$?
	#if echo $TESTNAME | grep -q pub; then
	#	#echo "joc públic: $TESTNAME"
	#	cat $LOCAL_SCRATCH/oo | ./canonprim.lua | sort -n > $LOCAL_SCRATCH/coo
	#	cmp --quiet $1/${TESTNAME}_out $LOCAL_SCRATCH/coo
	#	CMPR=$?
	#else
	#echo "joc privat: $TESTNAME"
	#fi
fi

if [ $1 != "6" -a $1 != "7" ]; then
	#echo "problema $1"
	#echo "joc de proves $TESTNAME"
	cmp --quiet $1/${TESTNAME}_out $LOCAL_SCRATCH/oo
	CMPR=$?
fi
#echo
#echo "COMPARISON RETURNED $CMPR "



if [ $CMPR == 0 ]; then
	#echo "MOLT BÉ, NOIS!"
	echo "joc de proves $TESTNAME: CORRECTE"
else
	echo "joc de proves $TESTNAME: INCORRECTE"
	echo -n "DIAGNÒSTIC: "
	cat $LOCAL_SCRATCH/oe | grep DIAG | cut -c16-
	touch $LOCAL_GSCRATCH/touchie
fi

# remove scratch dir
#rm -rf $LOCAL_SCRATCH


#
##
###
####
# EOF
####
###
##
#
