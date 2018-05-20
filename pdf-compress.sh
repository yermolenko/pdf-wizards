#!/bin/bash
#
#  pdf-compress - gs wrapper for reducing size of PDF files
#
#  Copyright (C) 2014, 2017, 2018 Alexander Yermolenko
#  <yaa.mbox@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

die()
{
    local msg=${1:-"Unknown error"}
    hash zenity 2>/dev/null && \
        zenity --error --title "Error" --text "ERROR: $msg"
    echo "ERROR: $msg" 1>&2
    exit 1
}

goodbye()
{
    local msg=${1:-"Cancelled by user"}
    hash zenity 2>/dev/null && \
        zenity --warning --title "Goodbye!" --text "$msg"
    echo "INFO: $msg" 1>&2
    exit 1
}

warning()
{
    local msg=${1:-"Info"}
    hash zenity 2>/dev/null && \
        zenity --warning --title "Warning!" --text "$msg"
    echo "WARNING: $msg" 1>&2
}

require()
{
    local cmd=${1:?"Command name is required"}
    local extra_info=${2:+"\nNote: $2"}
    hash $cmd 2>/dev/null || die "$cmd not found$extra_info"
}

require zenity
require gs "gs is part of Ghostscript, sudo apt-get install ghostscript"

CONF_FILE=~/.pdf-compress-0.1.conf

read_config()
{
    if [ -e "$CONF_FILE" ]
    then
        while IFS=':' read -ra fields; do
            var_name="${fields[0]}"
            var_value="${fields[1]}"
            if [ "$var_name" == "last_dir" ]
            then
                last_dir="$var_value"
                echo "last_dir:$last_dir"
                cd "$last_dir"
            fi
        done < "$CONF_FILE"
    fi
}

write_config()
{
    echo "last_dir:$last_dir" > $CONF_FILE
}

compress_pdf_via_gs()
{
    local pdf=${1:?"unspecified input pdf file name"}
    local compressed_pdf=${2:?"unspecified output pdf file name"}
    local img_resolution=${3:-"150"}

    gs \
        -dNOPAUSE -dBATCH -dSAFER \
        -sDEVICE=pdfwrite \
        -dCompatibilityLevel=1.4 \
        -dPDFSETTINGS=/screen \
        -dEmbedAllFonts=true \
        -dSubsetFonts=true \
        -dAutoRotatePages=/None \
        -dDownsampleColorImages=true \
        -dColorImageDownsampleType=/Bicubic	\
        -dColorImageResolution="$img_resolution" \
        -dGrayImageDownsampleType=/Bicubic \
        -dGrayImageResolution="$img_resolution" \
        -dMonoImageDownsampleType=/Bicubic \
        -dMonoImageResolution="$img_resolution" \
        -sOutputFile="$compressed_pdf" "$pdf" \
        | zenity --progress --pulsate --auto-close --title="PDF Compress" \
        || die "Cannot compress PDF using Ghostscript"
}

read_config

zenity \
    --info --title "Reduce PDF file size" \
    --text="The program reduces PDF file size\n\n\
Press OK to continue"

pdf=$( zenity \
           --file-selection \
           --title="Source PDF file" \
           --file-filter='*.pdf *.PDF' \
           --filename="$last_dir" )

case $? in
    0)
        echo "\"$pdf\" selected as original pdf.";;
    1)
        goodbye "No file selected";;
    -1)
        die "Error selecting file";;
esac

source_pdf_dir="$( dirname "$pdf" )/"

tempdir=$( mktemp -d )

cd "$tempdir" || die "Cannot cd to temp dir."

compressed_pdf="$( basename "$pdf" .pdf )-compressed.pdf"

if zenity \
       --question \
       --text="Do you want to shrink the file to a specific size?" \
       --ok-label="Yes. I want to set the size" \
       --cancel-label="No. I want more options";
then
    desired_file_size_in_kb=$( \
        zenity \
            --entry --title="Desired file size" \
            --text="Desired file size in kibibytes" \
            --entry-text "975" )

    case $? in
        0)
            echo "\"$desired_file_size_in_kb\" entered as desired file size in kibibytes.";;
        1)
            goodbye "No file size specified";;
        -1)
            die "Error selecting file size";;
    esac

    orig_file_size_kb=$(du -k "$pdf" | cut -f1)
    [ $orig_file_size_kb -lt $desired_file_size_in_kb ] && \
        goodbye "The file is alredy small enough"

    img_resolution1=20
    img_resolution2=600
    img_resolution=1

    iterations_limit=20
    iterations=0

    while true
    do
        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution2"
        file_size_kb2=$(du -k "$compressed_pdf" | cut -f1)

        [ $file_size_kb2 -lt $desired_file_size_in_kb ] && \
            { img_resolution=$img_resolution2; break; }

        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution1"
        file_size_kb1=$(du -k "$compressed_pdf" | cut -f1)

        img_resolution3=$(( ( $img_resolution1 + $img_resolution2 ) / 2 ))

        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution3"
        file_size_kb3=$(du -k "$compressed_pdf" | cut -f1)

        echo "Iteration: $iterations"
        echo "Raster image resolutions and file sizes:"
        echo "$img_resolution1 dpi : $file_size_kb1 KiB"
        echo "$img_resolution2 dpi : $file_size_kb2 KiB"
        echo "$img_resolution3 dpi : $file_size_kb3 KiB"

        [ $file_size_kb1 -lt $desired_file_size_in_kb ] && \
            [ $img_resolution1 -gt $img_resolution ] && \
            img_resolution=$img_resolution1 && \
            [ $(( ( $desired_file_size_in_kb - $file_size_kb1 ) * 100 )) -lt $(( $desired_file_size_in_kb * 7 )) ] && \
            break

        [ $file_size_kb2 -lt $desired_file_size_in_kb ] && \
            [ $img_resolution2 -gt $img_resolution ] && \
            img_resolution=$img_resolution2 && \
            [ $(( ( $desired_file_size_in_kb - $file_size_kb2 ) * 100 )) -lt $(( $desired_file_size_in_kb * 7 )) ] && \
            break

        [ $file_size_kb3 -lt $desired_file_size_in_kb ] && \
            [ $img_resolution3 -gt $img_resolution ] && \
            img_resolution=$img_resolution3 && \
            [ $(( ( $desired_file_size_in_kb - $file_size_kb3 ) * 100 )) -lt $(( $desired_file_size_in_kb * 7 )) ] && \
            break

        [ $file_size_kb3 -lt $desired_file_size_in_kb ] && \
            img_resolution1=$img_resolution3 || \
                img_resolution2=$img_resolution3

        iterations=$(( $iterations + 1 ))
        [ $iterations -gt $iterations_limit ] && break
    done

    compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution"
    resulted_file_size_kb=$(du -k "$compressed_pdf" | cut -f1)
    [ $resulted_file_size_kb -gt $desired_file_size_in_kb ] && \
        warning "Cannot achieve the desired size"
    echo "\"$img_resolution\" selected as image resolution."
else
    img_resolution=$( \
        zenity \
            --entry --title="Desired resolution of raster images" \
            --text="Desired resolution of raster images\n\n\
60 - bad quality; 300 - sufficient for printing\n" \
            --entry-text "150" )

    case $? in
        0)
            echo "\"$img_resolution\" entered as image resolution.";;
        1)
            goodbye "No resolution specified";;
        -1)
            die "Error selecting resolution";;
    esac

    compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution"
fi

while true
do
    output_pdf_real_default="$( dirname "$pdf" )/\
$( basename "$pdf" .pdf )-$( date +"%Y%m%d_%H%M%S" ).pdf"
    output_pdf_real=$( \
        zenity \
            --file-selection --title="Save result as" \
            --file-filter='*.pdf *.PDF' \
            --filename="$output_pdf_real_default" \
            --save )

    case $? in
        0)
            echo "\"$output_pdf_real\" selected as destination.";;
        1)
            goodbye "No file selected";;
        -1)
            die "Error selecting file";;
    esac

    if [ -e "$output_pdf_real" ]
    then
        if zenity \
               --question \
               --text="File $output_pdf_real already exists.\n\n\
Do you really want to replace it?" \
               --ok-label="Yes. Replace it, please." \
               --cancel-label="No! I still need it.";
        then
            break
        fi
    else
        break
    fi
done

mv "$compressed_pdf" "$output_pdf_real" || die "Cannot save the result"

rmdir "$tempdir" || die "Cannot remove temporary directory."

last_dir="$source_pdf_dir"

write_config

zenity \
    --info --title "Success!" \
    --text="It seems that all is success! Press OK and check the result."
