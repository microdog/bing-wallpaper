#!/usr/bin/env bash
# -*- coding: utf8 -*-

# Author: Hwasung Lee

# Register bing slideshows to Gnome desktop slideshows.
#
# This script registers a Gnome background slide show rotates between
#     Pictures/bing-wallpapers/today.jpg
# and
#     Pictures/bing-wallpapers/random.jpg
# The installed slideshow can target either the default picture directory or a
# user-provided --picturedir path.

set -euo pipefail

LOCAL_SHARE_DIR="$HOME/.local/share"
PROPERTIES_DIR="$LOCAL_SHARE_DIR/gnome-background-properties"
SLIDESHOW_DIR="$LOCAL_SHARE_DIR/background/slideshows"
PICTURE_DIR="$HOME/Pictures/bing-wallpapers"

usage() {
    cat <<EOF
Usage:
  deploy-gnome-settings.sh [--picturedir <picture dir>]

Options:
  --picturedir <picture dir>  Picture directory containing today.jpg/random.jpg.
                              Defaults to $HOME/Pictures/bing-wallpapers
  -h --help                   Show this screen.
EOF
}

normalize_picture_dir() {
    local path="$1"

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path=${path%/}
    done

    case "$path" in
        /*)
            printf '%s\n' "$path"
            ;;
        .)
            printf '%s\n' "$PWD"
            ;;
        *)
            printf '%s/%s\n' "$PWD" "$path"
            ;;
    esac
}

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g'
}

require_xml_representable_path() {
    local path="$1"
    local path_without_xml_safe_controls

    if ! printf '%s' "$path" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        printf 'Path cannot be represented in XML: %s\n' "$path" >&2
        exit 1
    fi

    path_without_xml_safe_controls=$(printf '%s' "$path" | LC_ALL=C tr -d '\11\12\15')
    if printf '%s' "$path_without_xml_safe_controls" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        printf 'Path cannot be represented in XML: %s\n' "$path" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --picturedir)
            if [[ $# -lt 2 ]]; then
                printf 'Option requires a value: %s\n' "$1" >&2
                exit 1
            fi
            PICTURE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown parameter: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

PICTURE_DIR=$(normalize_picture_dir "$PICTURE_DIR")
TODAY_PATH="$PICTURE_DIR/today.jpg"
RANDOM_PATH="$PICTURE_DIR/random.jpg"
SLIDESHOW_PATH="$SLIDESHOW_DIR/bing-today.xml"
require_xml_representable_path "$PICTURE_DIR"
require_xml_representable_path "$SLIDESHOW_PATH"
ESCAPED_TODAY_PATH=$(xml_escape "$TODAY_PATH")
ESCAPED_RANDOM_PATH=$(xml_escape "$RANDOM_PATH")
ESCAPED_SLIDESHOW_PATH=$(xml_escape "$SLIDESHOW_PATH")

mkdir -p "$PROPERTIES_DIR" "$SLIDESHOW_DIR"

cat >"$PROPERTIES_DIR/bing-slideshow.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper>
    <name>Bing's today wallpaper.</name>
    <filename>$ESCAPED_SLIDESHOW_PATH</filename>
    <options>zoom</options>
    <pcolor>#2c001e</pcolor>
    <scolor>#2c001e</scolor>
    <shade_type>solid</shade_type>
  </wallpaper>
</wallpapers>
EOF

cat >"$SLIDESHOW_PATH" <<EOF
<background>
  <starttime>
    <year>2013</year>
    <month>01</month>
    <day>01</day>
    <hour>00</hour>
    <minute>00</minute>
    <second>00</second>
  </starttime>
  <!-- Today's image for 10 mins. -->
  <static>
    <duration>600.0</duration>
    <file>$ESCAPED_TODAY_PATH</file>
  </static>
  <transition>
    <duration>5.0</duration>
    <from>$ESCAPED_TODAY_PATH</from>
    <to>$ESCAPED_RANDOM_PATH</to>
  </transition>

  <!-- Today's random image for 10 mins. -->
  <static>
    <duration>600.0</duration>
    <file>$ESCAPED_RANDOM_PATH</file>
  </static>
  <transition>
    <duration>5.0</duration>
    <from>$ESCAPED_RANDOM_PATH</from>
    <to>$ESCAPED_TODAY_PATH</to>
  </transition>
</background>
EOF
