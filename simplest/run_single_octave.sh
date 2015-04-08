#!/bin/sh


echo "<!-- running single (nonsecure version) $* -->"

IDENTITY="/home/coco/ipol/cipol/simplest/id_rsa.obama.priv"
EVIL="obama@localhost"
#JAIL="/home/jail"

LOCAL_SCRATCH_PART=scratches/ocipol_local_scratch
LOCAL_SCRATCH=/home/coco/ipol/cipol/simplest/$LOCAL_SCRATCH_PART
REMOTE_SCRATCH=/tmp/ocipol_remote_scratch

SETRLIM="/home/obama/bin/nurse AS 450000000 460000000 CPU 5 6 NPROC 14 15 NOFILE 10 10 FSIZE 5242880 5242880 --"

# check number of arguments
if [ $# != "1" ]; then
	echo "usage:\n\t ./run_single_octave.sh program.m"
	exit 1
fi


TAINTED_EXE=$1
#TAINTED_ARGS=$2

#UNTAINTED_ARGS=${TAINTED_ARGS}u
#cat $TAINTED_ARGS | tr \''\()[]#${}"&|^?' X >$UNTAINTED_ARGS



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

# create new remote scratch directory
ssh -i $IDENTITY $EVIL "rm -rf $REMOTE_SCRATCH && mkdir -p $REMOTE_SCRATCH && chmod a+w $REMOTE_SCRATCH"
if [ ! $? -eq 0 ]; then
	echo "ERROR: could not create remote scratch dir \"$REMOTE_SCRATCH\""
	exit 1
fi

## make symbolic link to static input data
ssh -i $IDENTITY $EVIL "cd $REMOTE_SCRATCH && ln -s /home/jail/etc/inputs ."
if [ ! $? -eq 0 ]; then
	echo "ERROR: could not link to static input data dir"
	exit 1
fi

#INPUT_PREFIX=000_
#SUNTAINTED_ARGS=""
#for i in `cat $UNTAINTED_ARGS`; do
#
#	ni=$i
#	ii=${JAIL}/etc/inputs/$i
#	if [ -s $ii ]; then
#		ni=$INPUT_PREFIX$i
#		cp $ii $JAIL$REMOTE_SCRATCH/$ni
#	fi
#	SUNTAINTED_ARGS="$SUNTAINTED_ARGS $ni"
#done
#echo $SUNTAINTED_ARGS > $UNTAINTED_ARGS


# copy executable file to remote scratch dir
cp $TAINTED_EXE ${JAIL}${REMOTE_SCRATCH} 2>>/tmp/ocipol_memme
if [ ! $? -eq 0 ]; then
	echo "ERROR: could not send program to remote scratch dir"
	exit 1
fi
# copy arguments file to remote scratch dir
#cp $UNTAINTED_ARGS ${JAIL}${REMOTE_SCRATCH} 2>>/tmp/ocipol_memmea
#if [ ! $? -eq 0 ]; then
#	echo "ERROR: could not send arguments to remote scratch dir"
#	exit 1
#fi


TBNAME=`basename $TAINTED_EXE`
#TBARGS=`cat $UNTAINTED_ARGS`

#######################
##  HERE BE DRAGONS  ##
#######################

# run the tainted executable on the scratch directory
#REMOTECMD="cd $REMOTE_SCRATCH && PLIMIT_CONFIG_FILE='' $SETRLIM ./$TBNAME $TBARGS >.o 2>.oe ; echo \$? >.or"
REMOTECMD="cd $REMOTE_SCRATCH && PLIMIT_CONFIG_FILE='' $SETRLIM /usr/bin/octave -fq $TBNAME >.o 2>.oe ; echo \$? >.or"
echo "<!--REMOTECMD=$REMOTECMD-->"
ssh -i $IDENTITY $EVIL "$REMOTECMD" 2> $LOCAL_SCRATCH/localoe
if [ ! $? -eq 0 ]; then
	echo "ERROR: something went worng! (exit code = $? )"
	echo "local error:"
	#cat $LOCAL_SCRATCH/localoe
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

# newly created images
for i in ${JAIL}${REMOTE_SCRATCH}/*.png ; do
	cp $i $LOCAL_SCRATCH/
done

# further misc output
cat $LOCAL_SCRATCH/oe | grep DIAG | cut -c16- > $LOCAL_SCRATCH/oediag
if [ -s $LOCAL_SCRATCH/oediag ]; then
	echo ""
	echo "<h3>Execution diagnostic:</h3><pre>"
	cat $LOCAL_SCRATCH/oediag
	echo "</pre>"
fi

# standard output
if [ -s $LOCAL_SCRATCH/oo ]; then
	echo ""
	echo "<h3>Standard output:</h3><pre>"
	cat $LOCAL_SCRATCH/oo
	echo "</pre>"
fi

# standard error
cat $LOCAL_SCRATCH/oe | grep -v "==NURSE==" > $LOCAL_SCRATCH/oe.nonurse
if [ -s $LOCAL_SCRATCH/oe.nonurse ]; then
	echo ""
	echo "<h3>Standard error:</h3><pre style=\"color:red\">"
	cat $LOCAL_SCRATCH/oe.nonurse
	echo "</pre>"
fi

# misc output
UPR=`cat $LOCAL_SCRATCH/or`
if [ "$UPR" != "0" ]; then
	echo ""
	echo "<h3>ssh error ($UPR):</h3><pre>"
	if [ -s $LOCAL_SCRATCH/localoe ]; then
		echo "LOCALOE:"
		cat $LOCAL_SCRATCH/localoe
	fi
	echo "</pre>"
fi

# display gallery contents
if ls $LOCAL_SCRATCH/*.png 2>/dev/null >/dev/null ; then
	first=`ls $LOCAL_SCRATCH/*.png|sed 1q`
	hfirst=`/home/coco/git/scratch/s2p/bin/imprintf %h $first 2>/tmp/what_oe`
	echo ""
	echo "<h3>Output images:</h3>"
	echo "<!-- first = \"${first}\" -->"
	echo "<!-- hfirst = \"${hfirst}\" -->"
	echo "<div class=\"gallery\" style=\"height:${hfirst}px\">"
	echo "  <ul class=\"index\">"
	randi=`cat /dev/urandom|od|head|md5sum|cut -c-9`
	for i in `ls $LOCAL_SCRATCH/*.png`; do
		bni=`basename $i`
		bnic=`basename $i .png|sed 's/[[:digit:]]*_//'`
		loci="$LOCAL_SCRATCH_PART/$bni"

		printf '    <li><a href="#">%s<span><img src="http://localhost:8910/%s?q=%s" /></span></a></li>\n' $bnic $loci $randi
		#printf '<img src="http://localhost:8910/%s" />' $loci
	done
	echo "  </ul>"
	echo "</div>"
fi


exit

#
##
###
####
# PARTIAL EOF
####
###
##
#
