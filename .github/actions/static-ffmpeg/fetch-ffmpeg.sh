#!/usr/bin/env bash
# Fetch and unpack the FFmpeg source into ./ffmpeg-$FFMPEG_VERSION.
# ffmpeg.org first (the canonical release tarball), then the GitHub tag
# archive: ffmpeg.org reset connections from the Windows runners for
# over an hour straight (it failed the v1.9.1 release's Windows job
# twice, an hour apart), and tag n<version> is the same source served
# from infrastructure Actions runners can always reach.
set -euo pipefail

fetch() {
	curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$2" "$1"
}

if fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
		"ffmpeg-${FFMPEG_VERSION}.tar.xz"; then
	tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
else
	echo "ffmpeg.org unreachable, using the GitHub mirror" >&2
	fetch "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz" \
		"ffmpeg-github.tar.gz"
	tar xf ffmpeg-github.tar.gz
	mv "FFmpeg-n${FFMPEG_VERSION}" "ffmpeg-${FFMPEG_VERSION}"
fi
