#!/bin/bash

set -e

if [ "$#" != "3" ]; then
	echo -e "usage\n\t$0 in.png URL out.png"
	#                    1      2   3
	false
fi

IMG_IN=$1
URL=$2
IMG_OUT=$3

WxH=`imprintf "%wx%h" $IMG_IN`
W=`echo $WxH | sed 's/x.*//'`
H=`echo $WxH | sed 's/.*x//'`

echo "W = $W"
echo "H = $H"

UMARGIN=94
RMARGIN=0

MINSIZE=351
if [ $W -lt 351 ]; then
	RMARGIN=$[MINSIZE-W]
fi

INVERSE_CMD="convert -extent $WxH+0+$UMARGIN $(basename $IMG_OUT) clean.png"

convert -extent $[W+RMARGIN]x$[H+UMARGIN]+0-$UMARGIN $IMG_IN \
	-draw "text 7,15 \"This image was created by an IPOL demo\"" \
	-fill blue \
	-draw "text 17,31 \"$URL\"" \
	-fill black \
	-draw "text 7,47 \"Please cite the corresponding article if you use this image.\"" \
	-font fixed \
	-fill green \
	-draw "text 7,69 \"To remove this comment with ImageMagick, run:\"" \
	-draw "text 7,83 \"$INVERSE_CMD\"" \
	$IMG_OUT






