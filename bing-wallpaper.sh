#!/usr/bin/env bash

SCRIPT=$(basename "${BASH_SOURCE[0]}")
VERSION='0.5.0'
RESOLUTIONS=(UHD 1920x1200 1920x1080 800x480 400x240)

readonly SCRIPT
readonly VERSION
readonly RESOLUTIONS

usage() {
cat <<EOF
Usage:
  $SCRIPT [options]
  $SCRIPT -h | --help
  $SCRIPT --version

Options:
  -f --force                     Force download of picture. This will overwrite
                                 the picture if the filename already exists.
  -s --ssl                       Communicate with bing.com over SSL.
  -b --boost <n>                 Use boost mode. Try to fetch latest <n> pictures.
  -q --quiet                     Do not display log messages.
  -n --filename <file name>      The name of the downloaded picture. Defaults to
                                 the upstream name.
  -p --picturedir <picture dir>  The full path to the picture download dir.
                                 Will be created if it does not exist.
                                 [default: $HOME/Pictures/bing-wallpapers/]
  -r --resolution <resolution>   The resolution of the image to retrieve.
                                 Supported resolutions:
                                 ${RESOLUTIONS[*]}
  -w --set-wallpaper             Set downloaded picture as wallpaper (Only mac support for now).
  -h --help                      Show this screen.
  --version                      Show version.
EOF
}

print_message() {
    if [[ -z "${QUIET}" ]]; then
        printf '%s\n' "$1"
    fi
}

print_error() {
    printf '%s\n' "$1" >&2
}

die() {
    print_error "$1"
    return 1
}

reset_state() {
    PICTURE_DIR="${HOME}/Pictures/bing-wallpapers/"
    RESOLUTION='1920x1080'
    BOOST='1'
    FILENAME=''
    FORCE=''
    QUIET=''
    SSL=''
    SET_WALLPAPER=''
    SHOW_HELP=''
    SHOW_VERSION=''
    PROTO='http'
    CURL_BIN="${BING_WALLPAPER_CURL_BIN:-curl}"
    OSASCRIPT_BIN="${BING_WALLPAPER_OSASCRIPT_BIN:-/usr/bin/osascript}"
    LAST_DOWNLOADED_FILE=''
    LAST_FILENAME=''
}

is_supported_resolution() {
    local candidate="$1"
    local supported

    for supported in "${RESOLUTIONS[@]}"; do
        if [[ "$supported" == "$candidate" ]]; then
            return 0
        fi
    done

    return 1
}

extract_image_urls_from_payload() {
    local payload="$1"
    local resolution="$2"
    local proto="$3"
    local remainder="$payload"
    local raw_url
    local normalized_url
    local match

    remainder=${remainder//$'\n'/ }
    remainder=${remainder//$'\r'/ }

    while [[ "$remainder" =~ \"url\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; do
        match="${BASH_REMATCH[0]}"
        raw_url="${BASH_REMATCH[1]}"
        normalized_url=$(printf '%s' "$raw_url" | sed "s/[0-9][0-9]*x[0-9][0-9]*/$resolution/g")

        case "$normalized_url" in
            http://*|https://*)
                printf '%s\n' "$normalized_url"
                ;;
            *)
                printf '%s://www.bing.com%s\n' "$proto" "$normalized_url"
                ;;
        esac

        remainder="${remainder#*"$match"}"
    done
}

derive_filename_from_url() {
    local url="$1"
    local filename

    if [[ "$url" == *'?id='* || "$url" == *'&id='* ]]; then
        filename="${url#*id=}"
        filename="${filename%%&*}"
    else
        filename="${url##*/}"
        filename="${filename%%\?*}"
    fi

    printf '%s\n' "${filename##*/}"
}

require_option_value() {
    local option="$1"
    local value="${2-}"

    if [[ -z "$value" ]] || [[ "$value" == -* ]]; then
        die "Option requires a value: $option"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--resolution)
                require_option_value "$1" "${2-}" || return 1
                RESOLUTION="$2"
                shift 2
                ;;
            -p|--picturedir)
                require_option_value "$1" "${2-}" || return 1
                PICTURE_DIR="$2"
                shift 2
                ;;
            -n|--filename)
                require_option_value "$1" "${2-}" || return 1
                FILENAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE='true'
                shift
                ;;
            -s|--ssl)
                SSL='true'
                shift
                ;;
            -b|--boost)
                require_option_value "$1" "${2-}" || return 1
                BOOST="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET='true'
                shift
                ;;
            -h|--help)
                SHOW_HELP='true'
                shift
                ;;
            -w|--set-wallpaper)
                SET_WALLPAPER='true'
                shift
                ;;
            --version)
                SHOW_VERSION='true'
                shift
                ;;
            *)
                print_error "Unknown parameter: $1"
                usage >&2
                return 1
                ;;
        esac
    done
}

validate_args() {
    if ! is_supported_resolution "$RESOLUTION"; then
        die "Unsupported resolution: $RESOLUTION"
        return 1
    fi

    if [[ ! "$BOOST" =~ ^[1-9][0-9]*$ ]]; then
        die "Boost must be a positive integer: $BOOST"
        return 1
    fi

    if [[ -n "$SSL" ]]; then
        PROTO='https'
    else
        PROTO='http'
    fi

    return 0
}

fetch_metadata() {
    "$CURL_BIN" -fsSL "${PROTO}://www.bing.com/HPImageArchive.aspx?format=js&n=${BOOST}"
}

download_image() {
    local image_url="$1"
    local target_path="$2"
    local filename="$3"
    local curl_args=()

    LAST_FILENAME="$filename"
    LAST_DOWNLOADED_FILE="$target_path"

    if [[ -z "$FORCE" && -f "$target_path" ]]; then
        print_message "Skipping: $filename..."
        return 0
    fi

    print_message "Downloading: $filename..."

    if [[ -n "$QUIET" ]]; then
        curl_args+=(-s)
    fi

    if "$CURL_BIN" "${curl_args[@]}" -Lo "$target_path" "$image_url"; then
        return 0
    fi

    rm -f "$target_path"
    return 1
}

set_macos_wallpaper() {
    local picture_path="$1"

    if [[ "$(uname -s)" != 'Darwin' ]]; then
        die 'Setting wallpaper is only supported on macOS.'
        return 1
    fi

    "$OSASCRIPT_BIN" <<EOF
tell application "System Events" to set picture of every desktop to ("$picture_path" as POSIX file as alias)
EOF
}

run_bing_wallpaper_impl() {
    local metadata_payload
    local image_url
    local filename
    local found_urls='0'

    reset_state
    parse_args "$@" || return 1

    if [[ -n "$SHOW_HELP" ]]; then
        usage
        return 0
    fi

    if [[ -n "$SHOW_VERSION" ]]; then
        printf '%s\n' "$VERSION"
        return 0
    fi

    validate_args || return 1
    mkdir -p "$PICTURE_DIR"
    metadata_payload=$(fetch_metadata) || return 1

    while IFS= read -r image_url; do
        if [[ -z "$image_url" ]]; then
            continue
        fi

        found_urls='1'

        if [[ -n "$FILENAME" ]]; then
            filename="$FILENAME"
        else
            filename=$(derive_filename_from_url "$image_url")
        fi

        download_image "$image_url" "${PICTURE_DIR%/}/$filename" "$filename" || return 1
    done < <(extract_image_urls_from_payload "$metadata_payload" "$RESOLUTION" "$PROTO")

    if [[ "$found_urls" != '1' ]]; then
        die 'No image URLs found in metadata response.'
    fi

    if [[ -n "$SET_WALLPAPER" ]]; then
        set_macos_wallpaper "$LAST_DOWNLOADED_FILE" || return 1
    fi
}

run_bing_wallpaper() {
    local script_path
    local state_file
    local status

    LAST_DOWNLOADED_FILE=''
    LAST_FILENAME=''
    script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
    state_file=$(mktemp "${TMPDIR:-/tmp}/bing-wallpaper-state.XXXXXX") || return 1

    if BING_WALLPAPER_STATE_FILE="$state_file" bash -euo pipefail -c '
        script_path=$1
        shift
        source "$script_path"
        run_bing_wallpaper_impl "$@"
        {
            printf "LAST_DOWNLOADED_FILE=%q\n" "$LAST_DOWNLOADED_FILE"
            printf "LAST_FILENAME=%q\n" "$LAST_FILENAME"
        } >"$BING_WALLPAPER_STATE_FILE"
    ' bash "$script_path" "$@"; then
        status=0
        # shellcheck disable=SC1090
        source "$state_file"
    else
        status=$?
    fi

    rm -f "$state_file"
    return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_bing_wallpaper "$@"
fi
