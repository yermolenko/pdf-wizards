#!/bin/bash
#
#  pdf-pages-to-pdf - producing PDF from a set of individual pages
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

CONF_FILE=~/.pdf-pages-to-pdf-0.1.conf

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
    --info --title "Combine Pages in PDF" \
    --text="The program produces PDF files from sets of invidivual pages\n\n\
Press OK to continue"

pages_dir=$( zenity \
                 --file-selection \
                 --directory \
                 --title="Directory with pages" \
                 --filename="$last_dir/" )

case $? in
    0)
        echo "\"$pages_dir\" selected as pages directory.";;
    1)
        goodbye "No directory selected";;
    -1)
        die "Error selecting directory";;
esac

pagefiles=()
while IFS= read -r file; do
    pagefiles+=("$file")
done < <(
    find "$pages_dir" -type f \
         \( -iname \*.jpeg -o -iname \*.jpg -o -iname \*.png -o -iname \*.pdf \) \
         -printf 'TRUE\n%f\n' | \
        zenity --list --checklist \
               --height=480 \
               --title "Select Files with Pages" \
               --text "Select files with pages to be included in the resulting PDF" \
               --column "Include" \
               --column "Filename" \
               --separator="\n"
)
# echo "${pagefiles[@]}"

[ ${#pagefiles[@]} -eq 0 ] && goodbye "No files with pages selected"

tempdir=$( mktemp -d )

cd "$tempdir" || die "Cannot cd to temp dir."

pagefile_pdfs=()
for pagefile in "${pagefiles[@]}"
do
    echo "Page: $pagefile"
    if [[ $(head -c 4 "$pages_dir/$pagefile") == "%PDF" ]]; then
        cp "$pages_dir/$pagefile" "$tempdir/$pagefile" &&
            pagefile_pdfs+=("$pagefile") || die "Cannot copy the file to tempdir"
    else
        convert -page a4 -density 72 "$pages_dir/$pagefile" "$tempdir/$pagefile.pdf" &&
            pagefile_pdfs+=("$pagefile.pdf") || die "Cannot make PDF from the page $pagefile"
    fi
done
# echo "${pagefile_pdfs[@]}"

output_pdf="$( mktemp --tmpdir="$tempdir" )"
#echo "$output_pdf"

pdftk "${pagefile_pdfs[@]}" cat output "$output_pdf" \
    || die "Cannot combine intermediate PDF files"

while true
do
    output_pdf_real_default="$pages_dir/\
$( basename "$pages_dir" .pdf )-$( date +"%Y%m%d_%H%M%S" ).pdf"
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

for pagefile_pdf in "${pagefile_pdfs[@]}"
do
    rm "$pagefile_pdf" || die "Cannot remove temporary files."
done
rmdir "$tempdir" || die "Cannot remove temporary directory."

last_dir="$pages_dir"

write_config

zenity \
    --info --title "Success!" \
    --text="It seems that all is success! Press OK and check the result."
