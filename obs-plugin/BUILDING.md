# Building the OBS plugin

The plugin is plain C and depends on **libobs** and **FFmpeg**
(`libavcodec`, `libavutil`) — the same FFmpeg OBS itself ships with.

## Linux

```bash
sudo apt install cmake build-essential pkg-config \
     libobs-dev libavcodec-dev libavutil-dev   # Debian/Ubuntu

cd obs-plugin
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build   # installs to /usr/local/lib/obs-plugins
```

If OBS was installed from the distro repos, you may need
`-DCMAKE_INSTALL_PREFIX=/usr` so the module lands next to the stock plugins.
Alternatively install per-user by copying manually:

```bash
mkdir -p ~/.config/obs-studio/plugins/ios-camera-source/bin/64bit \
         ~/.config/obs-studio/plugins/ios-camera-source/data
cp build/ios-camera-source.so ~/.config/obs-studio/plugins/ios-camera-source/bin/64bit/
cp -r data/* ~/.config/obs-studio/plugins/ios-camera-source/data/
```

## macOS

Build against an obs-studio checkout (Homebrew's `obs` does not ship dev
headers). With FFmpeg from Homebrew:

```bash
brew install cmake pkg-config ffmpeg
cd obs-plugin
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -Dlibobs_DIR=/path/to/obs-studio/build/libobs   # exported package
cmake --build build
```

Then copy into the app bundle / user plugin dir:

```bash
mkdir -p ~/Library/Application\ Support/obs-studio/plugins/ios-camera-source/bin
cp build/ios-camera-source.so ~/Library/Application\ Support/obs-studio/plugins/ios-camera-source/bin/
mkdir -p ~/Library/Application\ Support/obs-studio/plugins/ios-camera-source/data
cp -r data/* ~/Library/Application\ Support/obs-studio/plugins/ios-camera-source/data/
```

## Windows

Use the obs-studio dependency bundle (contains FFmpeg) and a built or
installed obs-studio tree:

```powershell
cmake -B build -G "Visual Studio 17 2022" -A x64 `
  -Dlibobs_DIR=C:\obs-studio\build\libobs `
  -DFFMPEG_INCLUDE_DIR=C:\obs-deps\include `
  -DAVCODEC_LIBRARY=C:\obs-deps\lib\avcodec.lib `
  -DAVUTIL_LIBRARY=C:\obs-deps\lib\avutil.lib
cmake --build build --config Release
```

Copy `build\Release\ios-camera-source.dll` to
`C:\Program Files\obs-studio\obs-plugins\64bit\` and the `data\` folder to
`C:\Program Files\obs-studio\data\obs-plugins\ios-camera-source\`.

## Verifying

Start OBS → *Sources* → **+** → **LensLink Camera**. The properties dialog shows
the connection settings and status. No inbound firewall rules are needed —
the plugin makes outbound connections to the phone.

## Translations

Every string the plugin shows (source properties, status lines, the
status bar, dock and settings dialog, and the browser control panel)
comes from `data/locale/<locale>.ini`. `en-US.ini` is the base; OBS loads
the file matching its own UI language (`de-DE.ini`, `ja-JP.ini`, …) and
falls back to English for any key a translation lacks.

- One `Key="Value"` per line, UTF-8 without BOM, no line breaks inside a
  value, and no `"` inside a value (use `'` or typographic quotes).
- Keep leading/trailing spaces exactly as in `en-US.ini`: values such as
  `Status.GreenScreen` are appended to other text.
- Browser panel strings are the `Web.*` keys. They are listed in
  `web_text_keys` in `src/web-control.c` and baked into the page once per
  OBS session, so a changed translation shows after an OBS restart.
- Status lines are built as label + value (`Status.Connected` + device
  name), never by using a translation as a format string.

Check the files after any change (standard-library Python):

```bash
python3 tools/l10n_plugin.py
```

It fails on malformed lines, duplicate keys, keys the sources use but
`en-US.ini` lacks (or the reverse), translation keys `en-US.ini` doesn't
have, empty translations and changed leading/trailing spaces; missing
translations are only warnings.
