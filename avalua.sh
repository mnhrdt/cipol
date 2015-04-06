#!/bin/sh

# usage:
# /path/to/avalua.sh {1|2|3...} TAINTED_EXECUTABLE >RESULTS_LINE

# This program runs ./avalua_single.sh for each test ("jocs de proves"), and
# summarizes the outputs

LOCAL_GSCRATCH=/tmp/graphie_local_gscratch



# check number of arguments
if [ $# != "2" ]; then
	echo "usage:\n\t ./avalua.sh dir executable >RESULTS"
	exit 1
fi

# check data consistency
if [ ! -d $1 ]; then
	echo "ERROR: el directori $1 no existeix"
	exit 1
fi
for i in $1/pub_[[:digit:]]_args $1/priv_[[:digit:]]{,[[:digit:]]}_args; do
	if [[ -f $i ]]; then
		#echo "i = $i"
		j=`echo $i | sed 's/_args/_out/'`
		#echo "j = $j"
		if [[ -f $i && -f $j ]]; then
			echo -n
			#echo "will run using $i $j"
		else
			echo "WARNING: $i or $j not found!"
		fi
		#echo
	fi
done

# build local gscratch dir
if [ -e $LOCAL_GSCRATCH ]; then
	rm -rf $LOCAL_GSCRATCH
fi
if [ -e $LOCAL_GSCRATCH ]; then
	echo "ERROR: could not clean local gscratch dir \"$LOCAL_GSCRATCH\""
	exit 1
fi
mkdir -p $LOCAL_GSCRATCH
if [ ! -e $LOCAL_GSCRATCH ]; then
	echo "ERROR: could not create local gscratch dir \"$LOCAL_GSCRATCH\""
	exit 1
fi

# run stuff
for i in $1/pub_[[:digit:]]_args $1/priv_[[:digit:]]{,[[:digit:]]}_args; do
	if [[ -f $i ]]; then
		ii=`basename $i | sed 's/_args//'`
		#echo "./avalua_single.sh $1 $ii $2"
		LOCAL_GSCRATCH=$LOCAL_GSCRATCH ./avalua_single.sh $1 $ii $2
		echo
		echo
		if [ -f $LOCAL_GSCRATCH/touchie ]; then
			exit 0
		fi
	fi
done
