#!/bin/bash
#
#  pdf-replace-page - pdftk wrapper for page replacing/adding
#
#  Copyright (C) 2014, 2017 Alexander Yermolenko <yaa.mbox@gmail.com>
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

require()
{
    local cmd=${1:?"Command name is required"}
    local extra_info=${2:+"\nNote: $2"}
    hash $cmd 2>/dev/null || die "$cmd not found$extra_info"
}

require zenity
require convert \
        "convert is part of ImageMagick, sudo apt-get install imagemagick"
require pdftk

CONF_FILE=~/.pdf-replace-page-0.1.conf

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

read_config

zenity \
    --info --title "Add/Replace Pages in PDF" \
    --text="The program performs adding/replacing pages in PDF files\n\n\
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

newpage_dir="$( dirname "$pdf" )/"

newpage=$( \
    zenity \
        --file-selection \
        --title="File containing new page(s) (JPG or PDF, JPG is preferred)" \
        --file-filter='*.pdf *.PDF *.jpg *.JPG *.jpeg *.JPEG *.png *.PNG' \
        --filename="$newpage_dir" )

case $? in
    0)
        echo "\"$newpage\" selected as new page.";;
    1)
        goodbye "No file selected";;
    -1)
        die "Error selecting file";;
esac

pages_total=$( pdftk "$pdf" dump_data | grep NumberOfPages | sed 's/[^0-9]*//' )
# echo "pages_total: $pages_total"

pageindex=$( \
    zenity \
        --entry --title="Page index" \
        --text="Index of the page to replace\n\n\
0 - insert in the front; (number of pages + 1) - append to the back\n\n\
Source PDF contains $pages_total pages.\n" \
        --entry-text "1" )

case $? in
    0)
        echo "\"$pageindex\" entered as page number.";;
    1)
        goodbye "No page index selected.";;
    -1)
        die "Error selecting page index.";;
esac

tempdir=$( mktemp -d )

cd "$tempdir" || die "Cannot cd to temp dir."

newpage_pdf="$( basename "$newpage" .pdf ).pdf"
#echo "$newpage_pdf"
convert -page a4 "$newpage" "$newpage_pdf" || die "Cannot convert page to PDF"

output_pdf="$( basename "$pdf" .pdf )-mod.pdf"
#echo "$output_pdf"

cut_start=$(( $pageindex - 1 ))
cut_end=$(( $pageindex + 1 ))
# echo $cut_start $cut_end

if [ $cut_start -ge 1 -a $cut_end -le $pages_total ]
then
    pdftk A="$newpage_pdf" B="$pdf" \
          cat B1-$cut_start A1 B$cut_end-end \
          output "$output_pdf" \
        || die "Merging has failed"
else
    if [ $cut_start -lt 1 ]
    then
        pdftk A="$newpage_pdf" B="$pdf" \
              cat A1 B$cut_end-end \
              output "$output_pdf" \
            || die "Merging has failed"
    fi
    if [ $cut_end -gt $pages_total ]
    then
        pdftk A="$newpage_pdf" B="$pdf" \
              cat B1-$cut_start A1 \
              output "$output_pdf" \
            || die "Merging has failed"
    fi
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

mv "$output_pdf" "$output_pdf_real" || die "Cannot save the result"

rm "$newpage_pdf" || die "Cannot remove temporary files."
rmdir "$tempdir" || die "Cannot remove temporary directory."

last_dir="$newpage_dir"

write_config

zenity \
    --info --title "Success!" \
    --text="It seems that all is success! Press OK and check the result."
