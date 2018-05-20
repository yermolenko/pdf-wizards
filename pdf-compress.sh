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
    local extra_info=${4:-"Changing resolution to $img_resolution dpi"}

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
                 --text="$extra_info"
}

read_config

zenity \
    --info --title "Уменьшение размера PDF" \
    --text="Эта программа предназначена для уменьшения размера PDF.\n\n\
Нажмите ОК для продолжения"

pdf=$( zenity \
           --file-selection \
           --title="Выберите исходный PDF файл" \
           --file-filter='*.pdf *.PDF' \
           --filename="$last_dir" )

case $? in
    0)
        echo "\"$pdf\" selected as original pdf.";;
    1)
        goodbye "Вы не выбрали файл";;
    -1)
        die "Ошибка при выборе файла";;
esac

source_pdf_dir="$( dirname "$pdf" )/"

tempdir=$( mktemp -d )

cd "$tempdir" || die "Cannot cd to temp dir."

compressed_pdf="$( basename "$pdf" .pdf )-compressed.pdf"

if zenity \
       --question \
       --text="Сжать файл до определённого размера?" \
       --ok-label="Да. Я хочу указать размер" \
       --cancel-label="Нет. Мне нужно больше опций";
then
    desired_file_size_in_kb=$( \
        zenity \
            --entry --title="Желаемый размер файла" \
            --text="Желаемый размер в кибибайтах" \
            --entry-text "975" )

    case $? in
        0)
            echo "\"$desired_file_size_in_kb\" entered as desired file size in kibibytes.";;
        1)
            goodbye "Вы не указали размер файла";;
        -1)
            die "Ошибка при выборе размера файла";;
    esac

    orig_file_size_kb=$(du -k "$pdf" | cut -f1)
    [ $orig_file_size_kb -lt $desired_file_size_in_kb ] && \
        goodbye "Файл уже достаточно малого размера"

    img_resolution1=20
    img_resolution2=600
    img_resolution=1

    iterations_limit=20
    iterations=0

    while true
    do
        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution2" || break
        file_size_kb2=$(du -k "$compressed_pdf" | cut -f1)

        [ $file_size_kb2 -lt $desired_file_size_in_kb ] && \
            { img_resolution=$img_resolution2; break; }

        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution1" || break
        file_size_kb1=$(du -k "$compressed_pdf" | cut -f1)

        img_resolution3=$(( ( $img_resolution1 + $img_resolution2 ) / 2 ))

        compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution3" || break
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

    compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution" \
                        "Finalizing with $img_resolution dpi. Please wait..." \
        || die "Cannot produce the result"
    resulted_file_size_kb=$(du -k "$compressed_pdf" | cut -f1)
    [ $resulted_file_size_kb -gt $desired_file_size_in_kb ] && \
        warning "Не могу достичь желаемого размера файла"
    echo "\"$img_resolution\" selected as image resolution."
else
    img_resolution=$( \
        zenity \
            --entry --title="Желаемое разрешение растровых изображений" \
            --text="Желаемое разрешение растровых изображений\n\n\
60 - плохое качество; 300 - достаточно для печати\n" \
            --entry-text "150" )

    case $? in
        0)
            echo "\"$img_resolution\" entered as image resolution.";;
        1)
            goodbye "Вы не указали разрешение";;
        -1)
            die "Ошибка при вводе разрешения";;
    esac

    compress_pdf_via_gs "$pdf" "$compressed_pdf" "$img_resolution"
fi

while true
do
    output_pdf_real_default="$( dirname "$pdf" )/\
$( basename "$pdf" .pdf )-$( date +"%Y%m%d_%H%M%S" ).pdf"
    output_pdf_real=$( \
        zenity \
            --file-selection --title="Сохранить результат как" \
            --file-filter='*.pdf *.PDF' \
            --filename="$output_pdf_real_default" \
            --save )

    case $? in
        0)
            echo "\"$output_pdf_real\" selected as destination.";;
        1)
            goodbye "Вы не выбрали файл";;
        -1)
            die "Ошибка при выборе файла";;
    esac

    if [ -e "$output_pdf_real" ]
    then
        if zenity \
               --question \
               --text="Файл $output_pdf_real уже существует. \
Вы действительно хотите его перезаписать?" \
               --ok-label="Да. Перезаписывай." \
               --cancel-label="Нет! Он мне ещё нужен.";
        then
            break
        fi
    else
        break
    fi
done

mv "$compressed_pdf" "$output_pdf_real" || die "Не получилось сохранить результат"

rmdir "$tempdir" || die "Cannot remove temporary directory."

last_dir="$source_pdf_dir"

write_config

zenity \
    --info --title "Завершено успешно!" \
    --text="Похоже, что всё получилось! Нажмите OK и проверьте результат."
