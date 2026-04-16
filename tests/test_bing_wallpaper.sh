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

assert_not_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        fail "$message
unexpected: $needle
actual:     $haystack"
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
request_args=$*
saw_fail=0

emit_metadata_payload() {
    local requested_count="$1"
    local payload
    local image_object
    local emitted_count=0

    payload=$(tr -d '\n\r' <"$metadata_payload")

    printf '{"images":['
    while [[ "$emitted_count" -lt "$requested_count" && "$payload" =~ (\{[^{}]*\"url\"[^{}]*\}) ]]; do
        image_object="${BASH_REMATCH[1]}"
        if [[ "$emitted_count" -gt 0 ]]; then
            printf ','
        fi
        printf '%s' "$image_object"
        emitted_count=$((emitted_count + 1))
        payload="${payload#*"$image_object"}"
    done
    printf ']}\n'
}

printf '%s\n' "$*" >>"$log_file"

out_file=
url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output|-Lo|-OL|-LO)
            out_file="$2"
            shift 2
            ;;
        -f|--fail)
            saw_fail=1
            shift
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
        requested_count=1
        if [[ "$url" =~ [\?\&]n=([0-9]+) ]]; then
            requested_count="${BASH_REMATCH[1]}"
        fi
        emit_metadata_payload "$requested_count"
        ;;
    *)
        if [[ -z "${out_file}" ]]; then
            printf 'missing output file\n' >&2
            exit 91
        fi
        if [[ "$download_mode" = "http-error-body" ]]; then
            printf '<html>404</html>\n' >"$out_file"
            if [[ "$saw_fail" -eq 1 ]]; then
                exit 22
            fi
            exit 0
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

run_cli_with_path() {
    local path_prefix="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    shift 3

    PATH="$path_prefix:$PATH" \
        BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub" \
        BING_WALLPAPER_OSASCRIPT_BIN="$TEST_TMPDIR/bin/osascript-stub" \
        bash "$SCRIPT_PATH" "$@" >"$stdout_file" 2>"$stderr_file"
}

run_cli_in_dir() {
    local run_dir="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    shift 3

    (
        cd "$run_dir" || exit 1
        BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub" \
            BING_WALLPAPER_OSASCRIPT_BIN="$TEST_TMPDIR/bin/osascript-stub" \
            bash "$SCRIPT_PATH" "$@" >"$stdout_file" 2>"$stderr_file"
    )
}

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkdir -p "$TEST_TMPDIR/bin"
make_curl_stub "$TEST_TMPDIR/bin/curl-stub"
cat >"$TEST_TMPDIR/bin/osascript-stub" <<'EOF'
#!/usr/bin/env bash

set -eu

if [[ $# -lt 1 || "$1" != "-" ]]; then
    printf "osascript expected '-' programfile before args, got: %s\n" "${1-<none>}" >&2
    exit 64
fi

shift

{
    printf 'PROGRAMFILE=-\n'
    printf 'APPLE_ARGC=%s\n' "$#"
    arg_index=0
    for arg in "$@"; do
        printf 'APPLE_ARGV[%d]=%s\n' "$arg_index" "$arg"
        arg_index=$((arg_index + 1))
    done
    printf 'STDIN:\n'
    cat
} >"$OSASCRIPT_STUB_LOG"

exit 0
EOF
chmod +x "$TEST_TMPDIR/bin/osascript-stub"
mkdir -p "$TEST_TMPDIR/fake-darwin"
cat >"$TEST_TMPDIR/fake-darwin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$TEST_TMPDIR/fake-darwin/uname"

HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
CURL_STUB_LOG="$TEST_TMPDIR/curl.log"
OSASCRIPT_STUB_LOG="$TEST_TMPDIR/osascript.log"
: >"$CURL_STUB_LOG"
: >"$OSASCRIPT_STUB_LOG"
CURL_STUB_METADATA_PAYLOAD="$FIXTURE_PATH"
export HOME CURL_STUB_LOG CURL_STUB_METADATA_PAYLOAD OSASCRIPT_STUB_LOG

HOST_OS=$(uname -s)

# shellcheck source=../bing-wallpaper.sh disable=SC1091
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

relative_version_stdout="$TEST_TMPDIR/relative-version.stdout"
relative_version_stderr="$TEST_TMPDIR/relative-version.stderr"
bash -lc 'cd "$1"; source ./bing-wallpaper.sh; cd /tmp; run_bing_wallpaper --version' bash "$ROOT_DIR" >"$relative_version_stdout" 2>"$relative_version_stderr"
assert_eq "0.5.0" "$(cat "$relative_version_stdout")" "relative-path sourced run_bing_wallpaper should still find the script after cd"
assert_eq "" "$(cat "$relative_version_stderr")" "relative-path sourced version call should not write to stderr"

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

negative_boost_stderr="$TEST_TMPDIR/negative-boost.stderr"
if run_cli "$TEST_TMPDIR/negative-boost.stdout" "$negative_boost_stderr" --boost -1; then
    fail "negative boost should fail"
fi
assert_eq "Boost must be a positive integer: -1" "$(cat "$negative_boost_stderr")" "negative boost should reach explicit boost validation"

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

boost_one_dir="$TEST_TMPDIR/boost-one-pictures"
boost_one_stdout="$TEST_TMPDIR/boost-one.stdout"
boost_one_stderr="$TEST_TMPDIR/boost-one.stderr"
run_cli "$boost_one_stdout" "$boost_one_stderr" --picturedir "$boost_one_dir" --boost 1
assert_file_exists "$boost_one_dir/OHR.SampleAlpha_1920x1080.jpg" "boost 1 should download the newest image"
assert_file_absent "$boost_one_dir/OHR.SampleBeta_1920x1080.jpg" "boost 1 should not download older images"

custom_filename_dir="$TEST_TMPDIR/custom-filename-pictures"
custom_filename_stdout="$TEST_TMPDIR/custom-filename.stdout"
custom_filename_stderr="$TEST_TMPDIR/custom-filename.stderr"
: >"$OSASCRIPT_STUB_LOG"
if ! run_cli_with_path "$TEST_TMPDIR/fake-darwin" "$custom_filename_stdout" "$custom_filename_stderr" --force --boost 2 --filename custom.jpg --set-wallpaper --picturedir "$custom_filename_dir"; then
    fail "Darwin-simulated custom filename wallpaper request should succeed"
fi
assert_file_exists "$custom_filename_dir/custom.jpg" "custom filename boost mode should leave the shared destination in place"
assert_eq "image-bytes:http://www.bing.com/th?id=OHR.SampleAlpha_1920x1080.jpg&rf=LaDigue_1920x1080.jpg&pid=hp" "$(cat "$custom_filename_dir/custom.jpg")" "custom filename boost mode should preserve the newest image bytes"
assert_contains "$custom_filename_dir/custom.jpg" "$(cat "$OSASCRIPT_STUB_LOG")" "custom filename boost mode should keep wallpaper targeting on the newest shared destination"
assert_eq "" "$(cat "$custom_filename_stderr")" "custom filename boost mode should not write to stderr"

dash_filename_stdout="$TEST_TMPDIR/dash-filename.stdout"
dash_filename_stderr="$TEST_TMPDIR/dash-filename.stderr"
run_cli "$dash_filename_stdout" "$dash_filename_stderr" --picturedir "$TEST_TMPDIR/dash-pictures" --filename -dash.jpg --boost 1
assert_file_exists "$TEST_TMPDIR/dash-pictures/-dash.jpg" "dash-prefixed filename should be accepted as an option value"

mkdir -p "$TEST_TMPDIR/dash-run"
dash_picturedir_stdout="$TEST_TMPDIR/dash-picturedir.stdout"
dash_picturedir_stderr="$TEST_TMPDIR/dash-picturedir.stderr"
run_cli_in_dir "$TEST_TMPDIR/dash-run" "$dash_picturedir_stdout" "$dash_picturedir_stderr" --picturedir -dashdir --boost 1
assert_file_exists "$TEST_TMPDIR/dash-run/-dashdir/OHR.SampleAlpha_1920x1080.jpg" "dash-prefixed picturedir should be accepted as an option value"

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

export CURL_STUB_DOWNLOAD_MODE=http-error-body
http_error_stdout="$TEST_TMPDIR/http-error.stdout"
http_error_stderr="$TEST_TMPDIR/http-error.stderr"
if run_cli "$http_error_stdout" "$http_error_stderr" --picturedir "$TEST_TMPDIR/http-error-pictures" --filename bad-http.jpg; then
    fail "HTTP error body download should fail"
fi
assert_file_absent "$TEST_TMPDIR/http-error-pictures/bad-http.jpg" "HTTP error body download should remove the target file"
unset CURL_STUB_DOWNLOAD_MODE

wallpaper_stderr="$TEST_TMPDIR/wallpaper.stderr"
wallpaper_stdout="$TEST_TMPDIR/wallpaper.stdout"
if [[ "$HOST_OS" = 'Darwin' ]]; then
    if ! run_cli "$wallpaper_stdout" "$wallpaper_stderr" --set-wallpaper --picturedir "$picturedir"; then
        fail "set-wallpaper should succeed on Darwin hosts"
    fi
    assert_eq "" "$(cat "$wallpaper_stderr")" "Darwin wallpaper request should not write to stderr"
    assert_file_exists "$picturedir/OHR.SampleAlpha_1920x1080.jpg" "Darwin wallpaper request should leave the downloaded file in place"
else
    if run_cli "$wallpaper_stdout" "$wallpaper_stderr" --set-wallpaper --picturedir "$picturedir"; then
        fail "set-wallpaper should fail on non-macOS hosts"
    fi
    assert_eq "Setting wallpaper is only supported on macOS." "$(cat "$wallpaper_stderr")" "non-macOS wallpaper request should fail with the exact required stderr"
fi

simulated_wallpaper_dir="$TEST_TMPDIR/simulated-wallpaper"
simulated_wallpaper_stdout="$TEST_TMPDIR/simulated-wallpaper.stdout"
simulated_wallpaper_stderr="$TEST_TMPDIR/simulated-wallpaper.stderr"
: >"$OSASCRIPT_STUB_LOG"
if ! run_cli_with_path "$TEST_TMPDIR/fake-darwin" "$simulated_wallpaper_stdout" "$simulated_wallpaper_stderr" --set-wallpaper --picturedir "$simulated_wallpaper_dir" --boost 2; then
    fail "Darwin-simulated set-wallpaper should succeed"
fi
assert_eq "" "$(cat "$simulated_wallpaper_stderr")" "Darwin-simulated wallpaper request should not write to stderr"
assert_contains "$simulated_wallpaper_dir/OHR.SampleAlpha_1920x1080.jpg" "$(cat "$OSASCRIPT_STUB_LOG")" "boosted wallpaper target should remain the newest image"

quoted_wallpaper_dir="$TEST_TMPDIR/quoted-\"wallpaper"
quoted_wallpaper_stdout="$TEST_TMPDIR/quoted-wallpaper.stdout"
quoted_wallpaper_stderr="$TEST_TMPDIR/quoted-wallpaper.stderr"
quoted_wallpaper_path="$quoted_wallpaper_dir/OHR.SampleAlpha_1920x1080.jpg"
: >"$OSASCRIPT_STUB_LOG"
if ! run_cli_with_path "$TEST_TMPDIR/fake-darwin" "$quoted_wallpaper_stdout" "$quoted_wallpaper_stderr" --set-wallpaper --picturedir "$quoted_wallpaper_dir" --boost 1; then
    fail "Darwin-simulated quoted wallpaper request should succeed"
fi
assert_eq "" "$(cat "$quoted_wallpaper_stderr")" "Darwin-simulated quoted wallpaper request should not write to stderr"
assert_file_exists "$quoted_wallpaper_path" "Darwin-simulated quoted wallpaper request should download the image"
assert_contains "PROGRAMFILE=-" "$(cat "$OSASCRIPT_STUB_LOG")" "quoted wallpaper path should use the stdin programfile marker"
assert_contains "APPLE_ARGC=1" "$(cat "$OSASCRIPT_STUB_LOG")" "quoted wallpaper path should be the only AppleScript user argument"
assert_contains "APPLE_ARGV[0]=$quoted_wallpaper_path" "$(cat "$OSASCRIPT_STUB_LOG")" "quoted wallpaper path should arrive as the first AppleScript argv entry"
assert_contains "item 1 of argv" "$(cat "$OSASCRIPT_STUB_LOG")" "quoted wallpaper path should be read from AppleScript argv"
assert_not_contains "set picture of every desktop to (\"$quoted_wallpaper_path\" as POSIX file as alias)" "$(cat "$OSASCRIPT_STUB_LOG")" "quoted wallpaper path should not be interpolated into the AppleScript source"

: >"$CURL_STUB_LOG"
state_tracking_stdout="$TEST_TMPDIR/state-tracking.stdout"
state_tracking_stderr="$TEST_TMPDIR/state-tracking.stderr"
export BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub"
export BING_WALLPAPER_OSASCRIPT_BIN="$TEST_TMPDIR/bin/osascript-stub"
if [[ "$HOST_OS" = 'Darwin' ]]; then
    if ! run_bing_wallpaper --picturedir "$TEST_TMPDIR/state-pictures" --set-wallpaper --boost 1 >"$state_tracking_stdout" 2>"$state_tracking_stderr"; then
        fail "sourced run_bing_wallpaper should succeed on Darwin hosts"
    fi
    assert_eq "" "$(cat "$state_tracking_stderr")" "Darwin sourced wallpaper request should not write to stderr"
    assert_file_exists "$TEST_TMPDIR/state-pictures/OHR.SampleAlpha_1920x1080.jpg" "Darwin sourced wallpaper request should leave the downloaded file in place"
else
    if run_bing_wallpaper --picturedir "$TEST_TMPDIR/state-pictures" --set-wallpaper --boost 1 >"$state_tracking_stdout" 2>"$state_tracking_stderr"; then
        fail "sourced run_bing_wallpaper should fail when wallpaper setting is unsupported"
    fi
    assert_eq "$TEST_TMPDIR/state-pictures/OHR.SampleAlpha_1920x1080.jpg" "$LAST_DOWNLOADED_FILE" "post-download failure should preserve LAST_DOWNLOADED_FILE"
    assert_eq "OHR.SampleAlpha_1920x1080.jpg" "$LAST_FILENAME" "post-download failure should preserve LAST_FILENAME"
fi

printf 'PASS test_bing_wallpaper (%d checks)\n' "$CHECKS"
