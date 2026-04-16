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

normalize_path_for_command() {
    local path="$1"

    if [[ "$path" == -* ]]; then
        printf './%s\n' "$path"
        return 0
    fi

    printf '%s\n' "$path"
}

run_bing_wallpaper "$@"

if [[ -z "${LAST_DOWNLOADED_FILE:-}" ]]; then
    printf 'Failed to determine the downloaded wallpaper path.\n' >&2
    exit 1
fi

picture_dir=$(dirname "$LAST_DOWNLOADED_FILE")
today_link="$picture_dir/today.jpg"
random_link="$picture_dir/random.jpg"
random_candidates=()

while IFS= read -r candidate; do
    if [[ "$candidate" != "$LAST_DOWNLOADED_FILE" ]]; then
        random_candidates[${#random_candidates[@]}]="$candidate"
    fi
done < <(find "$picture_dir" -maxdepth 1 -type f -name '*_*.jpg' | sort)

random_target="$LAST_DOWNLOADED_FILE"
if [[ ${#random_candidates[@]} -gt 0 ]]; then
    random_target="${random_candidates[RANDOM % ${#random_candidates[@]}]}"
fi

rm -f -- "$today_link" "$random_link"
ln -s "$(normalize_path_for_command "$LAST_DOWNLOADED_FILE")" \
    "$(normalize_path_for_command "$today_link")"
ln -s "$(normalize_path_for_command "$random_target")" \
    "$(normalize_path_for_command "$random_link")"
