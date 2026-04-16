#!/usr/bin/env bash
# -*- coding: utf8 -*-

# Author: Hwasung Lee

# This script downloads and links Bing's pictures to a fixed link.
#
# This script does three functions:
#   1. Execute bing-wallpaper script to download today's random picture.
#   2. Link it to $PICTURE_DIR/today.jpg
#   3. Randomly select a picture from $PICTURE_DIR/ that is not today's picture
#      and link it to $PICTURE_DIR/random.jpg
#
# Usage examples: (1) If the desktop background is set to $PICTURE_DIR/today.jpg
# this script will ensure it is always today's bing picture. (2) A Gnome
# slideshow can be setup to rotate between today.jpg and random.jpg. Look at the
# tools under gnome-bing-slideshow/

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
BING_SCRIPT="$SCRIPT_DIR/../bing-wallpaper.sh"

# shellcheck source=../bing-wallpaper.sh disable=SC1091
source "$BING_SCRIPT"

resolve_absolute_path() {
    local path="$1"
    local path_dir
    local path_base

    path_dir=$(dirname -- "$path")
    path_base=$(basename -- "$path")

    printf '%s/%s\n' "$(cd -- "$path_dir" && pwd -L)" "$path_base"
}

BING_WALLPAPER_SCRIPT_NAME=$(basename "$0")
export BING_WALLPAPER_SCRIPT_NAME
run_bing_wallpaper "$@"

current_downloaded_file=${CURRENT_DOWNLOADED_FILE:-${LAST_DOWNLOADED_FILE:-}}

if [[ -z "$current_downloaded_file" ]]; then
    exit 0
fi

downloaded_file=$(resolve_absolute_path "$current_downloaded_file")
picture_dir=$(dirname -- "$downloaded_file")
today_link="$picture_dir/today.jpg"
random_link="$picture_dir/random.jpg"
random_candidates=()

while IFS= read -r candidate; do
    if [[ "$candidate" != "$downloaded_file" ]]; then
        random_candidates[${#random_candidates[@]}]="$candidate"
    fi
done < <(find -- "$picture_dir" -maxdepth 1 -type f -name '*_*.jpg' | sort)

random_target="$downloaded_file"
if [[ ${#random_candidates[@]} -gt 0 ]]; then
    random_target="${random_candidates[RANDOM % ${#random_candidates[@]}]}"
fi

rm -f -- "$today_link" "$random_link"
ln -s -- "$downloaded_file" "$today_link"
ln -s -- "$random_target" "$random_link"
