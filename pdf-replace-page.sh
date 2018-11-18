#!/bin/bash
#
#  pdf-replace-page - pdftk wrapper for page replacing/adding
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
    --info --title "Добавление/замена страниц в PDF" \
    --text="Эта программа предназначена для добавления/замены страниц в PDF.\n\n\
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

newpage_dir="$( dirname "$pdf" )/"

newpage=$( \
    zenity \
        --file-selection \
        --title="Файл с новой страницей (JPG или PDF, лучше - JPG)" \
        --file-filter='*.pdf *.PDF *.jpg *.JPG *.jpeg *.JPEG *.png *.PNG' \
        --filename="$newpage_dir" )

case $? in
    0)
        echo "\"$newpage\" selected as new page.";;
    1)
        goodbye "Вы не выбрали файл";;
    -1)
        die "Ошибка при выборе файла";;
esac

pages_total=$( pdftk "$pdf" dump_data | grep NumberOfPages | sed 's/[^0-9]*//' )
# echo "pages_total: $pages_total"

pageindex=$( \
    zenity \
        --entry --title="Номер страницы" \
        --text="Номер страницы, которую нужно заменить\n\n\
0 - вставить перед всеми; (кол-во страниц + 1) - добавить в конец\n\n\
Всего в исходном документе $pages_total страниц.\n" \
        --entry-text "1" )

case $? in
    0)
        echo "\"$pageindex\" entered as page number.";;
    1)
        goodbye "Вы не указали номер страницы";;
    -1)
        die "Ошибка при выборе номера страницы";;
esac

tempdir=$( mktemp -d )

cd "$tempdir" || die "Cannot cd to temp dir."

newpage_pdf="$( basename "$newpage" .pdf ).pdf"
#echo "$newpage_pdf"
if [[ $(head -c 4 "$newpage") == "%PDF" ]]; then
    cp "$newpage" "$newpage_pdf" || die "Не получилось подготовить PDF-страницу"
else
    convert -page a4 -density 72 "$newpage" "$newpage_pdf" || die "Не получилось преобразовать страницу в PDF"
fi

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
        || die "Что-то пошло не так при объединении документа"
else
    if [ $cut_start -lt 1 ]
    then
        pdftk A="$newpage_pdf" B="$pdf" \
              cat A1 B$cut_end-end \
              output "$output_pdf" \
            || die "Что-то пошло не так при объединении документа"
    fi
    if [ $cut_end -gt $pages_total ]
    then
        pdftk A="$newpage_pdf" B="$pdf" \
              cat B1-$cut_start A1 \
              output "$output_pdf" \
            || die "Что-то пошло не так при объединении документа"
    fi
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

mv "$output_pdf" "$output_pdf_real" || die "Не получилось сохранить результат"

rm "$newpage_pdf" || die "Cannot remove temporary files."
rmdir "$tempdir" || die "Cannot remove temporary directory."

last_dir="$newpage_dir"

write_config

zenity \
    --info --title "Завершено успешно!" \
    --text="Похоже, что всё получилось! Нажмите OK и проверьте результат."
