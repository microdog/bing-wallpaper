#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_PATH="$ROOT_DIR/tests/fixtures/hpimagearchive-sample.json"
RANDOM_HELPER="$ROOT_DIR/Tools/bing-random-pic.sh"
GNOME_HELPER="$ROOT_DIR/Tools/gnome-bing-slideshow/deploy-gnome-settings.sh"

CHECKS=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass_check() {
    CHECKS=$((CHECKS + 1))
}

assert_status_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$actual" -ne "$expected" ]]; then
        fail "$message
expected: $expected
actual:   $actual"
    fi

    pass_check
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
expected substring: $needle
actual:             $haystack"
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

run_random_helper() {
    local run_dir="$1"
    shift

    (
        cd -- "$run_dir" || exit 1
        bash "$RANDOM_HELPER" "$@"
    )
}

run_random_helper_with_payload() {
    local payload_path="$1"
    local run_dir="$2"
    shift 2

    CURL_STUB_METADATA_PAYLOAD="$payload_path" run_random_helper "$run_dir" "$@"
}

make_curl_stub() {
    local stub_path="$1"

    cat >"$stub_path" <<'EOF'
#!/usr/bin/env bash

set -eu

metadata_payload=${CURL_STUB_METADATA_PAYLOAD:?}

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

out_file=
url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output|-Lo|-OL|-LO)
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
        requested_count=1
        if [[ "$url" =~ [\?\&]n=([0-9]+) ]]; then
            requested_count="${BASH_REMATCH[1]}"
        fi
        emit_metadata_payload "$requested_count"
        ;;
    *)
        if [[ -z "$out_file" ]]; then
            printf 'missing output file\n' >&2
            exit 91
        fi
        printf 'image-bytes:%s\n' "$url" >"$out_file"
        ;;
esac
EOF
    chmod +x "$stub_path"
}

extract_first_fixture_url() {
    local payload

    payload=$(tr -d '\n\r' <"$FIXTURE_PATH")
    if [[ "$payload" =~ \"url\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    fail "fixture payload did not contain a wallpaper URL"
}

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkdir -p "$TEST_TMPDIR/bin"
make_curl_stub "$TEST_TMPDIR/bin/curl-stub"

HOME="$TEST_TMPDIR/home with spaces"
mkdir -p "$HOME"
export HOME

single_image_payload="$TEST_TMPDIR/single-image.json"
printf '{"images":[{"url":"%s"}]}\n' "$(extract_first_fixture_url)" >"$single_image_payload"
export CURL_STUB_METADATA_PAYLOAD="$single_image_payload"
export BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub"

version_stdout="$TEST_TMPDIR/helper-version.stdout"
version_stderr="$TEST_TMPDIR/helper-version.stderr"
if run_random_helper "$ROOT_DIR" --version >"$version_stdout" 2>"$version_stderr"; then
    version_status=0
else
    version_status=$?
fi

assert_status_eq 0 "$version_status" "wrapper --version should succeed"
assert_eq "0.5.0" "$(cat "$version_stdout")" "wrapper --version should forward version output"
assert_eq "" "$(cat "$version_stderr")" "wrapper --version should not write wrapper errors"

help_stdout="$TEST_TMPDIR/helper-help.stdout"
help_stderr="$TEST_TMPDIR/helper-help.stderr"
if run_random_helper "$ROOT_DIR" --help >"$help_stdout" 2>"$help_stderr"; then
    help_status=0
else
    help_status=$?
fi

help_output=$(cat "$help_stdout")

assert_status_eq 0 "$help_status" "wrapper --help should succeed"
assert_contains "bing-random-pic.sh [options]" "$help_output" "wrapper --help should identify the helper script"
assert_eq "" "$(cat "$help_stderr")" "wrapper --help should not write wrapper errors"

picture_dir="$TEST_TMPDIR/pictures dir"
run_random_helper_with_payload "$single_image_payload" "$ROOT_DIR" --quiet --picturedir "$picture_dir"

today_target=$(readlink "$picture_dir/today.jpg")
random_target=$(readlink "$picture_dir/random.jpg")
expected_target="$picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$expected_target" "$today_target" "today.jpg should point to the downloaded image"
assert_eq "$expected_target" "$random_target" "random.jpg should fall back to today's image when no alternate image exists"

boost_one_picture_dir="$TEST_TMPDIR/pictures boost one"
run_random_helper_with_payload "$FIXTURE_PATH" "$ROOT_DIR" --quiet --boost 1 --picturedir "$boost_one_picture_dir"

boost_one_today_target=$(readlink "$boost_one_picture_dir/today.jpg")
boost_one_random_target=$(readlink "$boost_one_picture_dir/random.jpg")
boost_one_expected_target="$boost_one_picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$boost_one_expected_target" "$boost_one_today_target" "boost 1 should keep today.jpg on the newest image"
assert_eq "$boost_one_expected_target" "$boost_one_random_target" "boost 1 should keep random.jpg on the only downloaded image"
assert_file_absent "$boost_one_picture_dir/OHR.SampleBeta_1920x1080.jpg" "boost 1 should not download older helper images"

custom_filename_picture_dir="$TEST_TMPDIR/pictures custom filename"
run_random_helper_with_payload "$FIXTURE_PATH" "$ROOT_DIR" --quiet --force --boost 2 --filename custom.jpg --picturedir "$custom_filename_picture_dir"

custom_filename_today_target=$(readlink "$custom_filename_picture_dir/today.jpg")
custom_filename_random_target=$(readlink "$custom_filename_picture_dir/random.jpg")
custom_filename_expected_target="$custom_filename_picture_dir/custom.jpg"

assert_eq "$custom_filename_expected_target" "$custom_filename_today_target" "custom filename boost mode should keep today.jpg on the newest shared destination"
assert_eq "$custom_filename_expected_target" "$custom_filename_random_target" "custom filename boost mode should make random.jpg fall back to the only shared destination"
assert_eq "image-bytes:http://www.bing.com/th?id=OHR.SampleAlpha_1920x1080.jpg&rf=LaDigue_1920x1080.jpg&pid=hp" "$(cat "$custom_filename_picture_dir/custom.jpg")" "custom filename boost mode should preserve the newest image bytes for helper symlinks"
assert_file_absent "$custom_filename_picture_dir/OHR.SampleBeta_1920x1080.jpg" "custom filename boost mode should not create an alternate helper image when sharing one destination"

dash_run_dir="$TEST_TMPDIR/dash helper run"
mkdir -p "$dash_run_dir"
run_random_helper_with_payload "$single_image_payload" "$dash_run_dir" --quiet --picturedir -dashdir

dash_today_path="$dash_run_dir/-dashdir/today.jpg"
dash_random_path="$dash_run_dir/-dashdir/random.jpg"
dash_expected_target="$dash_run_dir/-dashdir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$dash_expected_target" "$(readlink "$dash_today_path")" "today.jpg should work for dash-prefixed relative picture directories"
assert_eq "$dash_expected_target" "$(readlink "$dash_random_path")" "random.jpg should fall back correctly for dash-prefixed relative picture directories"
assert_file_exists "$dash_today_path" "today.jpg symlink should resolve for dash-prefixed relative picture directories"
assert_file_exists "$dash_random_path" "random.jpg symlink should resolve for dash-prefixed relative picture directories"

alternate_picture_dir="$TEST_TMPDIR/pictures with alternates"
run_random_helper_with_payload "$FIXTURE_PATH" "$ROOT_DIR" --quiet --boost 2 --picturedir "$alternate_picture_dir"

alternate_today_target=$(readlink "$alternate_picture_dir/today.jpg")
alternate_random_target=$(readlink "$alternate_picture_dir/random.jpg")
alternate_today_expected="$alternate_picture_dir/OHR.SampleAlpha_1920x1080.jpg"
alternate_random_expected="$alternate_picture_dir/OHR.SampleBeta_1920x1080.jpg"

assert_eq "$alternate_today_expected" "$alternate_today_target" "today.jpg should point to the newest downloaded image when alternates exist"
assert_eq "$alternate_random_expected" "$alternate_random_target" "random.jpg should point to a non-today wallpaper when alternates exist"
assert_file_exists "$alternate_picture_dir/OHR.SampleAlpha_1920x1080.jpg" "alternate wallpaper candidate should exist on disk"
assert_file_exists "$alternate_picture_dir/random.jpg" "random.jpg symlink should resolve when alternates exist"

bash "$GNOME_HELPER"

assert_file_exists "$HOME/.local/share/gnome-background-properties/bing-slideshow.xml" "deploy helper should copy the GNOME background properties XML"
assert_file_exists "$HOME/.local/share/background/slideshows/bing-today.xml" "deploy helper should copy the slideshow XML"

printf 'PASS test_helpers (%d checks)\n' "$CHECKS"
