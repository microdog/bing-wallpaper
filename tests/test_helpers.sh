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

make_slow_extractor_override() {
    local override_path="$1"

    cat >"$override_path" <<'EOF'
inject_bing_test_override() {
    if [[ ${BASH_COMMAND:-} == 'run_bing_wallpaper_impl "$@"' ]]; then
        extract_image_urls_from_payload() {
            local i

            printf '%s\n' 'http://www.bing.com/th?id=OHR.SampleAlpha_1920x1080.jpg&pid=hp'
            for ((i = 1; i <= 100; i++)); do
                sleep 0.01
                printf '%s\n' "http://www.bing.com/th?id=OHR.SampleBeta${i}_1920x1080.jpg&pid=hp"
            done
        }

        trap - DEBUG
    fi
}

trap inject_bing_test_override DEBUG
EOF
}

make_curl_stub() {
    local stub_path="$1"

    cat >"$stub_path" <<'EOF'
#!/usr/bin/env bash

set -eu

metadata_payload=${CURL_STUB_METADATA_PAYLOAD:?}
download_mode=${CURL_STUB_DOWNLOAD_MODE:-success}
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
        if [[ -z "$out_file" ]]; then
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

HOME="$TEST_TMPDIR/home & spaces"
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

logical_root="$TEST_TMPDIR/logical helper root"
physical_root="$TEST_TMPDIR/physical helper root"
mkdir -p "$physical_root"
ln -s "$physical_root" "$logical_root"
logical_picture_dir="$logical_root/pictures via symlink"
run_random_helper_with_payload "$single_image_payload" "$ROOT_DIR" --quiet --picturedir "$logical_picture_dir"

logical_today_target=$(readlink "$logical_picture_dir/today.jpg")
logical_random_target=$(readlink "$logical_picture_dir/random.jpg")
logical_expected_target="$logical_picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$logical_expected_target" "$logical_today_target" "today.jpg should preserve logical picture directory paths"
assert_eq "$logical_expected_target" "$logical_random_target" "random.jpg should preserve logical picture directory paths"

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

slow_override_path="$TEST_TMPDIR/slow-extractor-override.sh"
slow_custom_stdout="$TEST_TMPDIR/slow-custom.stdout"
slow_custom_stderr="$TEST_TMPDIR/slow-custom.stderr"
slow_custom_picture_dir="$TEST_TMPDIR/pictures custom filename slow"
make_slow_extractor_override "$slow_override_path"
if BASH_ENV="$slow_override_path" run_random_helper "$ROOT_DIR" --quiet --force --boost 2 --filename custom.jpg --picturedir "$slow_custom_picture_dir" >"$slow_custom_stdout" 2>"$slow_custom_stderr"; then
    slow_custom_status=0
else
    slow_custom_status=$?
fi

assert_status_eq 0 "$slow_custom_status" "slow extractor helper run should still succeed for a shared custom filename"
assert_eq "" "$(cat "$slow_custom_stderr")" "slow extractor helper run should not leak broken-pipe stderr"
assert_eq "image-bytes:http://www.bing.com/th?id=OHR.SampleAlpha_1920x1080.jpg&pid=hp" "$(cat "$slow_custom_picture_dir/custom.jpg")" "slow extractor helper run should keep the first custom-filename download"

http_error_helper_dir="$TEST_TMPDIR/http-error-helper"
http_error_helper_stdout="$TEST_TMPDIR/http-error-helper.stdout"
http_error_helper_stderr="$TEST_TMPDIR/http-error-helper.stderr"
if CURL_STUB_DOWNLOAD_MODE=http-error-body run_random_helper_with_payload "$single_image_payload" "$ROOT_DIR" --quiet --picturedir "$http_error_helper_dir" >"$http_error_helper_stdout" 2>"$http_error_helper_stderr"; then
    fail "helper should fail on HTTP error body downloads"
fi
assert_file_absent "$http_error_helper_dir/today.jpg" "helper should not link today.jpg after an HTTP error body"
assert_file_absent "$http_error_helper_dir/random.jpg" "helper should not link random.jpg after an HTTP error body"
assert_file_absent "$http_error_helper_dir/OHR.SampleAlpha_1920x1080.jpg" "helper should clean up the failed HTTP error body target"

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

custom_gnome_picture_dir="$TEST_TMPDIR/custom gnome wallpapers"
bash "$GNOME_HELPER" --picturedir "$custom_gnome_picture_dir"

custom_slideshow_path="$HOME/.local/share/background/slideshows/bing-today.xml"
custom_properties_path="$HOME/.local/share/gnome-background-properties/bing-slideshow.xml"
assert_eq "$custom_gnome_picture_dir/today.jpg" "$(xmllint --xpath 'string(/background/static[1]/file)' "$custom_slideshow_path")" "deploy helper should point today.jpg at the requested picture directory"
assert_eq "$custom_gnome_picture_dir/random.jpg" "$(xmllint --xpath 'string(/background/static[2]/file)' "$custom_slideshow_path")" "deploy helper should point random.jpg at the requested picture directory"
assert_eq "$custom_slideshow_path" "$(xmllint --xpath 'string(/wallpapers/wallpaper/filename)' "$custom_properties_path")" "deploy helper should point the GNOME properties XML at the installed slideshow XML"

escaped_gnome_picture_dir="$TEST_TMPDIR/custom & gnome <wallpapers>"
bash "$GNOME_HELPER" --picturedir "$escaped_gnome_picture_dir"

assert_eq "$escaped_gnome_picture_dir/today.jpg" "$(xmllint --xpath 'string(/background/static[1]/file)' "$custom_slideshow_path")" "deploy helper should preserve today.jpg after XML parsing for escaped paths"
assert_eq "$escaped_gnome_picture_dir/random.jpg" "$(xmllint --xpath 'string(/background/static[2]/file)' "$custom_slideshow_path")" "deploy helper should preserve random.jpg after XML parsing for escaped paths"
assert_eq "$custom_slideshow_path" "$(xmllint --xpath 'string(/wallpapers/wallpaper/filename)' "$custom_properties_path")" "deploy helper should keep the properties XML valid for escaped paths"

invalid_xml_picture_dir="$TEST_TMPDIR/invalid"$'\f'"xml"
invalid_xml_stdout="$TEST_TMPDIR/invalid-xml.stdout"
invalid_xml_stderr="$TEST_TMPDIR/invalid-xml.stderr"
if bash "$GNOME_HELPER" --picturedir "$invalid_xml_picture_dir" >"$invalid_xml_stdout" 2>"$invalid_xml_stderr"; then
    fail "deploy helper should reject XML-unrepresentable picture directories"
fi
assert_contains "Path cannot be represented in XML" "$(cat "$invalid_xml_stderr")" "deploy helper should explain XML-unrepresentable picture directories"

printf 'PASS test_helpers (%d checks)\n' "$CHECKS"
