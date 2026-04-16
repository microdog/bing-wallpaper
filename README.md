Bing Wallpaper for macOS and GNOME Linux
========================================

`bing-wallpaper.sh` downloads the current Bing homepage image into a local
directory. The maintained scope is:

- macOS: download support plus `--set-wallpaper`
- Linux: reliable download support plus the GNOME helper scripts in `Tools/`

Usage
-----

Run the script directly to download the current Bing homepage image:

```bash
./bing-wallpaper.sh
```

The default download directory is `$HOME/Pictures/bing-wallpapers/`. Use
`--help` to see the full public CLI:

```text
Usage:
  bing-wallpaper.sh [options]
  bing-wallpaper.sh -h | --help
  bing-wallpaper.sh --version

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
                                 UHD 1920x1200 1920x1080 800x480 400x240
  -w --set-wallpaper             Set downloaded picture as wallpaper (Only mac support for now).
  -h --help                      Show this screen.
  --version                      Show version.
```

Examples:

```bash
./bing-wallpaper.sh --ssl --boost 2
./bing-wallpaper.sh --picturedir "$HOME/Pictures/bing" --resolution UHD
./bing-wallpaper.sh --set-wallpaper
```

macOS
-----

On macOS, the maintained workflow is:

1. Download the image with `./bing-wallpaper.sh`
2. Optionally set it immediately with `./bing-wallpaper.sh --set-wallpaper`
3. Automate the script with `launchd` if you want a daily refresh

A sample LaunchAgent plist is provided at
`Tools/com.ideasftw.bing-wallpaper.plist`. Copy it to
`$HOME/Library/LaunchAgents/`, update the script path to match your local
checkout, and load it:

```bash
cp Tools/com.ideasftw.bing-wallpaper.plist "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.ideasftw.bing-wallpaper.plist"
```

If you prefer to rotate through the downloaded directory in System Settings,
point Wallpaper at your chosen picture directory.

GNOME Linux
-----------

On Linux, the maintained path is using `bing-wallpaper.sh` for reliable
downloads and the GNOME helper scripts when you want slideshow-style rotation.

The GNOME helper workflow is:

1. Run `./bing-wallpaper.sh` on a schedule to keep the directory populated
2. Or run `Tools/bing-random-pic.sh` when you want one command that downloads
   the current image and refreshes the `today.jpg` and `random.jpg` symlinks
   for GNOME
3. Run `Tools/gnome-bing-slideshow/deploy-gnome-settings.sh` once per user to
   install the slideshow XML files into `~/.local/share/`
4. In GNOME Settings, choose the installed Bing slideshow background

Example setup:

```bash
bash Tools/bing-random-pic.sh --picturedir "$HOME/Pictures/bing-wallpapers"
bash Tools/gnome-bing-slideshow/deploy-gnome-settings.sh
```

To automate downloads or helper refreshes, use your preferred scheduler. The
repository includes `Tools/bing-cron` as a cron example that you can adapt to
your local paths.
