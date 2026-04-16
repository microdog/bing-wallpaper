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

CURL_STUB_METADATA_PAYLOAD="$FIXTURE_PATH"
single_image_payload="$TEST_TMPDIR/single-image.json"
printf '{"images":[{"url":"%s"}]}\n' "$(extract_first_fixture_url)" >"$single_image_payload"
CURL_STUB_METADATA_PAYLOAD="$single_image_payload"
export CURL_STUB_METADATA_PAYLOAD
export BING_WALLPAPER_CURL_BIN="$TEST_TMPDIR/bin/curl-stub"

picture_dir="$TEST_TMPDIR/pictures dir"
bash "$RANDOM_HELPER" --quiet --picturedir "$picture_dir"

today_target=$(readlink "$picture_dir/today.jpg")
random_target=$(readlink "$picture_dir/random.jpg")
expected_target="$picture_dir/OHR.SampleAlpha_1920x1080.jpg"

assert_eq "$expected_target" "$today_target" "today.jpg should point to the downloaded image"
assert_eq "$expected_target" "$random_target" "random.jpg should fall back to today's image when no alternate image exists"

bash "$GNOME_HELPER"

assert_file_exists "$HOME/.local/share/gnome-background-properties/bing-slideshow.xml" "deploy helper should copy the GNOME background properties XML"
assert_file_exists "$HOME/.local/share/background/slideshows/bing-today.xml" "deploy helper should copy the slideshow XML"

printf 'PASS test_helpers (%d checks)\n' "$CHECKS"
