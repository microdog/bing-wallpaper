#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_PATH="$ROOT_DIR/tests/fixtures/hpimagearchive-sample.json"
SCRIPT_PATH="$ROOT_DIR/bing-wallpaper.sh"

CHECKS=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass_check() {
    CHECKS=$((CHECKS + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$actual" != "$expected" ]]; then
        fail "$message
expected: $expected
actual:   $actual"
    fi

    pass_check
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$message
missing: $needle
actual:  $haystack"
    fi

    pass_check
}

assert_file_exists() {
    local path="$1"
    local message="$2"

    [[ -f "$path" ]] || fail "$message ($path)"
    pass_check
}

assert_file_absent() {
    local path="$1"
    local message="$2"

    [[ ! -e "$path" ]] || fail "$message ($path)"
    pass_check
}

assert_status_nonzero() {
    local status="$1"
    local message="$2"

    [[ "$status" -ne 0 ]] || fail "$message"
    pass_check
}

make_curl_stub() {
    local stub_path="$1"

    cat >"$stub_path" <<'EOF'
#!/usr/bin/env bash

set -eu

log_file=${CURL_STUB_LOG:?}
metadata_payload=${CURL_STUB_METADATA_PAYLOAD:?}
download_mode=${CURL_STUB_DOWNLOAD_MODE:-success}

printf '%s\n' "$*" >>"$log_file"

out_file=
url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|-Lo|-OL|-LO)
            out_file="$2"
            shift 2
            ;;
        -L|-s|-S|-f)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

case "$url" in
    *HPImageArchive.aspx*)
        cat "$metadata_payload"
        ;;
    *)
        if [[ -z "${out_file}" ]]; then
            printf 'missing output file\n' >&2
            exit 91
        fi
        if [[ "$download_mode" = "fail" ]]; then
            printf 'partial download' >"$out_file"
            exit 17
        fi
        printf 'image-bytes:%s\n' "$url" >"$out_file"
        ;;
esac
EOF
    chmod +x "$stub_path"
}

run_cli() {
    local stdout_file="$1"
    local stderr_file="$2"
    shift 2

    BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub" \
        BING_WALLPAPER_OSASCRIPT_BIN="$TEST_TMPDIR/bin/osascript-stub" \
        bash "$SCRIPT_PATH" "$@" >"$stdout_file" 2>"$stderr_file"
}

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkdir -p "$TEST_TMPDIR/bin"
make_curl_stub "$TEST_TMPDIR/bin/curl-stub"
cat >"$TEST_TMPDIR/bin/osascript-stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_TMPDIR/bin/osascript-stub"

HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
CURL_STUB_LOG="$TEST_TMPDIR/curl.log"
: >"$CURL_STUB_LOG"
CURL_STUB_METADATA_PAYLOAD="$FIXTURE_PATH"
export HOME CURL_STUB_LOG CURL_STUB_METADATA_PAYLOAD

source "$SCRIPT_PATH"

payload=$(cat "$FIXTURE_PATH")
extracted_urls=()
while IFS= read -r extracted_url; do
    extracted_urls[${#extracted_urls[@]}]="$extracted_url"
done < <(extract_image_urls_from_payload "$payload" "UHD" "https")
assert_eq "2" "${#extracted_urls[@]}" "extract_image_urls_from_payload should return two URLs"
assert_eq "https://www.bing.com/th?id=OHR.SampleAlpha_UHD.jpg&rf=LaDigue_UHD.jpg&pid=hp" "${extracted_urls[0]}" "first URL should be normalized to requested resolution"
assert_eq "OHR.SampleAlpha_UHD.jpg" "$(derive_filename_from_url "${extracted_urls[0]}")" "derive_filename_from_url should preserve upstream filename"

version_stdout="$TEST_TMPDIR/version.stdout"
version_stderr="$TEST_TMPDIR/version.stderr"
run_cli "$version_stdout" "$version_stderr" --version
assert_eq "0.5.0" "$(cat "$version_stdout")" "--version should print script version"
assert_eq "" "$(cat "$version_stderr")" "--version should not write to stderr"

invalid_resolution_stderr="$TEST_TMPDIR/invalid-resolution.stderr"
if run_cli "$TEST_TMPDIR/invalid-resolution.stdout" "$invalid_resolution_stderr" --resolution 123x456; then
    fail "invalid resolution should fail"
fi
assert_contains "Unsupported resolution: 123x456" "$(cat "$invalid_resolution_stderr")" "invalid resolution should explain the failure"

invalid_boost_stderr="$TEST_TMPDIR/invalid-boost.stderr"
if run_cli "$TEST_TMPDIR/invalid-boost.stdout" "$invalid_boost_stderr" --boost nope; then
    fail "invalid boost should fail"
fi
assert_contains "Boost must be a positive integer: nope" "$(cat "$invalid_boost_stderr")" "invalid boost should explain the failure"

: >"$CURL_STUB_LOG"
blocked_stdout="$TEST_TMPDIR/blocked.stdout"
blocked_stderr="$TEST_TMPDIR/blocked.stderr"
if run_cli "$blocked_stdout" "$blocked_stderr" --picturedir /dev/null/blocked --boost 1; then
    fail "blocked picturedir should fail"
fi
assert_eq "" "$(cat "$blocked_stdout")" "blocked picturedir should exit before printing download progress"
assert_eq "" "$(cat "$CURL_STUB_LOG")" "blocked picturedir should exit before invoking curl"

picturedir="$TEST_TMPDIR/pictures"
success_stdout="$TEST_TMPDIR/success.stdout"
success_stderr="$TEST_TMPDIR/success.stderr"
run_cli "$success_stdout" "$success_stderr" --picturedir "$picturedir" --boost 2
assert_file_exists "$picturedir/OHR.SampleAlpha_1920x1080.jpg" "successful download should create first image"
assert_file_exists "$picturedir/OHR.SampleBeta_1920x1080.jpg" "successful download should create second image"

: >"$CURL_STUB_LOG"
skip_stdout="$TEST_TMPDIR/skip.stdout"
skip_stderr="$TEST_TMPDIR/skip.stderr"
run_cli "$skip_stdout" "$skip_stderr" --picturedir "$picturedir" --boost 1
assert_contains "Skipping: OHR.SampleAlpha_1920x1080.jpg..." "$(cat "$skip_stdout")" "existing file should be skipped without --force"

export CURL_STUB_DOWNLOAD_MODE=fail
failure_stdout="$TEST_TMPDIR/failure.stdout"
failure_stderr="$TEST_TMPDIR/failure.stderr"
if run_cli "$failure_stdout" "$failure_stderr" --picturedir "$TEST_TMPDIR/fail-pictures" --filename failing.jpg; then
    fail "failed download should return non-zero"
fi
assert_file_absent "$TEST_TMPDIR/fail-pictures/failing.jpg" "failed download should remove partial file"
unset CURL_STUB_DOWNLOAD_MODE

wallpaper_stderr="$TEST_TMPDIR/wallpaper.stderr"
if run_cli "$TEST_TMPDIR/wallpaper.stdout" "$wallpaper_stderr" --set-wallpaper --picturedir "$picturedir"; then
    fail "set-wallpaper should fail on non-macOS hosts"
fi
assert_eq "Setting wallpaper is only supported on macOS." "$(cat "$wallpaper_stderr")" "non-macOS wallpaper request should fail with the exact required stderr"

: >"$CURL_STUB_LOG"
state_tracking_stdout="$TEST_TMPDIR/state-tracking.stdout"
state_tracking_stderr="$TEST_TMPDIR/state-tracking.stderr"
export BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub"
export BING_WALLPAPER_OSASCRIPT_BIN="$TEST_TMPDIR/bin/osascript-stub"
if run_bing_wallpaper --picturedir "$TEST_TMPDIR/state-pictures" --set-wallpaper --boost 1 >"$state_tracking_stdout" 2>"$state_tracking_stderr"; then
    fail "sourced run_bing_wallpaper should fail when wallpaper setting is unsupported"
fi
assert_eq "$TEST_TMPDIR/state-pictures/OHR.SampleBeta_1920x1080.jpg" "$LAST_DOWNLOADED_FILE" "post-download failure should preserve LAST_DOWNLOADED_FILE"
assert_eq "OHR.SampleBeta_1920x1080.jpg" "$LAST_FILENAME" "post-download failure should preserve LAST_FILENAME"

printf 'PASS test_bing_wallpaper (%d checks)\n' "$CHECKS"
