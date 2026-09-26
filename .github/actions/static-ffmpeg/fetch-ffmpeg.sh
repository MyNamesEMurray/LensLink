#!/usr/bin/env bash
# Fetch and unpack the FFmpeg source into ./ffmpeg-$FFMPEG_VERSION.
# ffmpeg.org first (the canonical release tarball), then the GitHub
# mirror: ffmpeg.org reset connections from the Windows runners for
# over an hour straight (it failed the v1.9.1 release's Windows job
# twice, an hour apart), and tag n<version> is the same source served
# from infrastructure Actions runners can always reach.
set -euo pipefail

case "$FFMPEG_VERSION" in
7.1)
	tarball_sha256=40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6
	tag_commit=b08d7969c550a804a59511c7b83f2dd8cc0499b8
	;;
*)
	echo "::error::No pinned checksums for FFmpeg $FFMPEG_VERSION: add them to fetch-ffmpeg.sh" >&2
	exit 1
	;;
esac

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

tarball="ffmpeg-${FFMPEG_VERSION}.tar.xz"
if curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$tarball" \
		"https://ffmpeg.org/releases/$tarball" &&
	[ "$(sha256 "$tarball")" = "$tarball_sha256" ]; then
	tar xf "$tarball"
	exit 0
fi

echo "ffmpeg.org unreachable or checksum mismatch, using the GitHub mirror" >&2
dir="ffmpeg-${FFMPEG_VERSION}"
rm -rf "$dir"
git init -q "$dir"
for attempt in 1 2 3 4 5; do
	if git -C "$dir" fetch -q --depth 1 \
			https://github.com/FFmpeg/FFmpeg.git "$tag_commit"; then
		break
	fi
	[ "$attempt" -lt 5 ] || exit 1
	sleep 2
done
git -C "$dir" -c core.autocrlf=false checkout -q FETCH_HEAD
[ "$(git -C "$dir" rev-parse HEAD)" = "$tag_commit" ]
rm -rf "$dir/.git"
