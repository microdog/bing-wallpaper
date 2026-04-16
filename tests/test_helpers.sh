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

assert_file_exists() {
    local path="$1"
    local message="$2"

    [[ -f "$path" ]] || fail "$message ($path)"
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
        cat "$metadata_payload"
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

picture_dir="$TEST_TMPDIR/pictures dir"
run_random_helper_with_payload "$single_image_payload" "$ROOT_DIR" --quiet --picturedir "$picture_dir"

today_target=$(readlink "$picture_dir/today.jpg")
random_target=$(readlink "$picture_dir/random.jpg")
expected_target="$picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$expected_target" "$today_target" "today.jpg should point to the downloaded image"
assert_eq "$expected_target" "$random_target" "random.jpg should fall back to today's image when no alternate image exists"

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
run_random_helper_with_payload "$FIXTURE_PATH" "$ROOT_DIR" --quiet --picturedir "$alternate_picture_dir"

alternate_today_target=$(readlink "$alternate_picture_dir/today.jpg")
alternate_random_target=$(readlink "$alternate_picture_dir/random.jpg")
alternate_today_expected="$alternate_picture_dir/OHR.SampleBeta_1920x1080.jpg"
alternate_random_expected="$alternate_picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$alternate_today_expected" "$alternate_today_target" "today.jpg should point to the latest downloaded image when alternates exist"
assert_eq "$alternate_random_expected" "$alternate_random_target" "random.jpg should point to a non-today wallpaper when alternates exist"
assert_file_exists "$alternate_picture_dir/OHR.SampleAlpha_1920x1080.jpg" "alternate wallpaper candidate should exist on disk"
assert_file_exists "$alternate_picture_dir/random.jpg" "random.jpg symlink should resolve when alternates exist"

bash "$GNOME_HELPER"

assert_file_exists "$HOME/.local/share/gnome-background-properties/bing-slideshow.xml" "deploy helper should copy the GNOME background properties XML"
assert_file_exists "$HOME/.local/share/background/slideshows/bing-today.xml" "deploy helper should copy the slideshow XML"

printf 'PASS test_helpers (%d checks)\n' "$CHECKS"
