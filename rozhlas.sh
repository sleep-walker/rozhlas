#!/bin/bash

source ~/swlib.sh

monitor=(
    "http://www.rozhlas.cz/dvojka/pohadky/"
    "http://www.rozhlas.cz/dvojka/stream/"
)

downloaded_list=/home/tcech/.rozhlas-downloaded
location="/data/Hudba/rozhlas"
trap cleanup SIGINT SIGQUIT

cleanup() {
    rm -f "${tmp_files[@]}"
    exit 0
}

add_tmp() {
    local _tmp="$(mktemp)"
    tmp_files[${#tmp_files[@]}]="$_tmp"
    eval "$1"="'$_tmp'"
}

htmldecode() {
    perl -e 'use HTML::Entities;binmode(STDOUT, ":utf8");print decode_entities($ARGV[0]), "\n";' "$1"
}

httpget() {
    local out="$(wget "$@")"
    local ret=$?
    if [ $ret -ne 0 ]; then
	echo "$out"
	return $ret
    fi
}

get_xpath_attribute() {
    echo "cat $1" | xmllint --shell --html "$tmp" 2>/dev/null | sed -n "s/^ ${1##*@}=\"\([^\"]*\)\"/\1/p"
}

get_mp3_from_page() {
    local tmp
    add_tmp tmp
    httpget "$1" -O "$tmp"
    local id="$(get_xpath_attribute "//div/@data-id")"
    local label="$(htmldecode "$(get_xpath_attribute "//div/@data-event_label")")"
    if [ -z "$id" -o -z "$label" ]; then
	error "Problem decoding $1"
	failed_urls[${#failed_urls[@]}]="$1"
	return 1
    fi
    if grep "^$id\$" "$downloaded_list" &> /dev/null; then
	inform "ID $id already downloaded."
	return 0
    fi

    filename="$(sed 's@ \[[0-9]\+\]@@;s@ @_@g;s@: @-@g;s@(\([0-9]\+\)/\([0-9]\+\))@(\1_z_\2)@' <<< "$label").mp3"
    inform "Downloading recording with id $id as $filename."
    httpget "http://media.rozhlas.cz/_audio/$id.mp3" -O "$location/$filename"
    echo "$id" >> "$downloaded_list"
}


get_list() {
    local tmp
    add_tmp tmp
    httpget "$1" -O "$tmp" -q
    readarray -t -O "${#urls[@]}" urls < <(get_xpath_attribute "//li[@class=\"item\"]/div/a/@href" | sort -u | sed 's@^@http://www.rozhlas.cz@')
}

generate_urls() {
    for mon in "${monitor[@]}"; do
	get_list "$mon"
    done
}

urls=()
failed_urls=()
tmp_files=()
generate_urls

inform "Found URLs:"
( export IFS=$'\n'; echo "${urls[*]}"; )
for i in "${urls[@]}"; do
    get_mp3_from_page "$i"
done

if [ ${#failed_urls[@]} -gt 0 ]; then
    error "Failed URLs:"
    ( export IFS=$'\n'; echo "${failed_urls[*]}"; ) | tee ~/.rozhlas-failures
fi

