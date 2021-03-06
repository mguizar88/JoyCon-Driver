#!/bin/bash
#
#
# This bash script regenerates the HTML doxygen version of the
# wxWidgets manual and adjusts the doxygen log to make it more
# readable.
#
# Usage:
#    ./regen.sh [html|chm|xml|latex|all]
#
# Pass "x" to regen only the X output format and "all" to regen them all.
# If no arguments are passed all formats are regenerated
# (just like passing "all").
#


# remember current folder and then cd to the docs/doxygen one
me=$(basename $0)
path=${0%%/$me}        # path from which the script has been launched
current=$(pwd)
cd $path
if [[ -z "$WXWIDGETS" ]]; then
    # Notice the use of -P to ensure we get the canonical path even if there
    # are symlinks in the current path. This is important because Doxygen
    # strips this string from the paths in the generated files textually and it
    # wouldn't work if it contained symlinks.
    WXWIDGETS=`cd ../.. && pwd -P`
    if [ "$OSTYPE" = "cygwin" ]; then
        WXWIDGETS=`cygpath -w $WXWIDGETS`
    fi
    export WXWIDGETS
fi

if [ "$DOXYGEN" = "" ]; then
    DOXYGEN=doxygen
fi

# Check that doxygen has the correct version as different versions of it are
# unfortunately not always (in fact, practically never) compatible.
#
# Still allow using incompatible version if explicitly requested.
if [[ -z $WX_SKIP_DOXYGEN_VERSION_CHECK ]]; then
    doxygen_version=`$DOXYGEN --version`
    doxygen_version_required=1.8.8
    if [[ $doxygen_version != $doxygen_version_required ]]; then
        echo "Doxygen version $doxygen_version is not supported."
        echo "Please use Doxygen $doxygen_version_required or export WX_SKIP_DOXYGEN_VERSION_CHECK."
        exit 1
    fi
fi

# prepare folders for the cp commands below
mkdir -p out/html       # we need to copy files in this folder below
mkdir -p out/html/generic

# These are not automatically copied by Doxygen because they're not
# used in doxygen documentation, only in our html footer and by our
# custom aliases
cp images/generic/*png out/html/generic

# Defaults for settings controlled by this script
export GENERATE_DOCSET="NO";
export GENERATE_HTML="NO";
export GENERATE_HTMLHELP="NO";
export GENERATE_LATEX="NO";
export GENERATE_QHP="NO";
export GENERATE_XML="NO";
export SEARCHENGINE="NO";
export SERVER_BASED_SEARCH="NO";

# Which format should we generate during this run?
case "$1" in
    all) # All *main* formats, not all formats, here for backwards compat.
        export GENERATE_HTML="YES";
        export GENERATE_HTMLHELP="YES";
        export GENERATE_XML="YES";
        ;;
    chm)
        export GENERATE_HTML="YES";
        export GENERATE_HTMLHELP="YES";
        ;;
    docset)
        export GENERATE_DOCSET="YES";
        export GENERATE_HTML="YES";
        ;;
    latex)
        export GENERATE_LATEX="YES";
        ;;
    php) # HTML, but with PHP Search Engine
        export GENERATE_HTML="YES";
        export SEARCHENGINE="YES";
        export SERVER_BASED_SEARCH="YES";
        ;;
    qch)
        export GENERATE_HTML="YES";
        export GENERATE_QHP="YES";
        ;;
    xml)
        export GENERATE_XML="YES";
        ;;
    *) # Default to HTML only
        export GENERATE_HTML="YES";
        export SEARCHENGINE="YES";
        ;;
esac

#
# NOW RUN DOXYGEN
#
# NB: we do this _after_ copying the required files to the output folders
#     otherwise when generating the CHM file with Doxygen, those files are
#     not included!
#
$DOXYGEN Doxyfile

if [[ "$1" = "qch" ]]; then
    # we need to add missing files to the .qhp
    cd out/html
    qhelpfile="index.qhp"

    # remove all <file> and <files> tags
    cat $qhelpfile | grep -v "<file" >temp

    # remove last 4 lines (so we have nothing after the last <keyword> tag)
    lines=$(wc -l < temp)
    wanted=`expr $lines - 4`
    head -n $wanted temp >$qhelpfile

    # generate a list of new <keyword> tags to add to the index file; without
    # this step in the 'index' tab of Qt assistant the "wxWindow" class is not
    # present; just "wxWindow::wxWindow" ctor is listed.
    # NOTE: this operation is not indispensable but produces a QCH easier to use IMO.
    sed -e 's/<keyword name="wx[a-zA-Z~]*" id="wx\([a-zA-Z]*\)::[a-zA-Z~]*" ref="\([a-z_]*.html\)#.*"/<keyword name="wx\1" id="wx\1" ref="\2"/g' < $qhelpfile | grep "<keyword name=\"wx" | uniq >temp
    cat temp >>$qhelpfile
    echo "    </keywords>" >>$qhelpfile
    echo "    <files>" >>$qhelpfile

    # remove useless files to make the qch slim
    rm temp *map *md5

    # add a <file> tag for _any_ file in out/html folder except the .qhp itself
    for f in * */*png; do
        if [[ $f != $qhelpfile ]]; then
            echo "      <file>$f</file>" >>$qhelpfile
        fi
    done

    # add ending tags to the qhp file
    echo "    </files>
  </filterSection>
</QtHelpProject>" >>$qhelpfile

    # replace keyword names so that they appear fully-qualified in the
    # "index" tab of the Qt Assistant; e.g. Fit => wxWindow::Fit
    # NOTE: this operation is not indispendable but produces a QCH easier to use IMO.
    sed -e 's/<keyword name="[a-zA-Z:~]*" id="\([a-zA-Z]*::[a-zA-Z~]*\)"/<keyword name="\1" id="\1"/g' <$qhelpfile >temp
    mv temp $qhelpfile

    # last, run qhelpgenerator:
    cd ../..
    qhelpgenerator out/html/index.qhp -o out/wx.qch
fi

if [[ "$1" = "docset" ]]; then
    BASENAME="wxWidgets-3.0"    # was org.wxwidgets.doxygen.docset.wx30
    DOCSETNAME="$BASENAME.docset"
    ATOM="$BASENAME.atom"
    ATOMDIR="http://docs.wxwidgets.org/docsets"
    XAR="$BASENAME.xar"
    XARDIR="http://docs.wxwidgets.org/docsets"
    XCODE_INSTALL=`xcode-select -print-path`
    
    cd out/html
    DESTINATIONDIR=`pwd`/../docset
    
    mkdir -p $DESTINATIONDIR
    rm -rf $DESTINATIONDIR/$DOCSETNAME
    rm -f $DESTINATIONDIR/$XAR
    
    make DOCSET_NAME=$DESTINATIONDIR/$DOCSETNAME
    
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info CFBundleVersion 1.3
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info CFBundleShortVersionString 1.3
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info CFBundleName "wxWidgets 3.0"
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info DocSetFeedURL $ATOMDIR/$ATOM
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info DocSetFallbackURL http://docs.wxwidgets.org
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info DocSetDescription "API reference and conceptual documentation for wxWidgets 3.0"
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info NSHumanReadableCopyright "Copyright 1992-2014 wxWidgets team, Portions 1996 Artificial Intelligence Applications Institute"
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info isJavaScriptEnabled true
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info dashIndexFilePath index.html
    defaults write $DESTINATIONDIR/$DOCSETNAME/Contents/Info DocSetPlatformFamily wx

    $XCODE_INSTALL/usr/bin/docsetutil package -atom $DESTINATIONDIR/$ATOM -download-url $XARDIR/$XAR -output $DESTINATIONDIR/$XAR $DESTINATIONDIR/$DOCSETNAME

    cd ../..
fi

# Doxygen has the annoying habit to put the full path of the
# affected files in the log file; remove it to make the log
# more readable
currpath=`pwd`/
interfacepath=`cd ../../interface && pwd`/
cat doxygen.log | sed -e "s|$currpath||g" -e "s|$interfacepath||g" > temp
cat temp > doxygen.log
rm temp

# return to the original folder from which this script was launched
cd $current
