#!/usr/bin/env bash
# -*- coding: utf8 -*-

# Author: Hwasung Lee

# Register bing slideshows to Gnome desktop slideshows.
#
# This script registers a Gnome background slide show rotates between
#     Pictures/bing-wallpapers/today.jpg
# and
#     Pictures/bing-wallpapers/random.jpg
# Tested for Ubuntu versions 12.04 - 13.10.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LOCAL_SHARE_DIR="$HOME/.local/share"
PROPERTIES_DIR="$LOCAL_SHARE_DIR/gnome-background-properties"
SLIDESHOW_DIR="$LOCAL_SHARE_DIR/background/slideshows"

mkdir -p "$PROPERTIES_DIR" "$SLIDESHOW_DIR"

cp "$SCRIPT_DIR/dot_local/share/gnome-background-properties/bing-slideshow.xml" \
    "$PROPERTIES_DIR/bing-slideshow.xml"
cp "$SCRIPT_DIR/dot_local/share/background/slideshows/bing-today.xml" \
    "$SLIDESHOW_DIR/bing-today.xml"
