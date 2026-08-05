#!/usr/bin/env bash
# Runs under the runner's stock MSYS2 with the MSVC (vcvars64)
# environment inherited — see action.yml. Produces static
# avcodec.lib/avutil.lib in $GITHUB_WORKSPACE/ffmpeg-static.
set -euxo pipefail

# MSYS2's coreutils /usr/bin/link shadows MSVC's link.exe, and FFmpeg's
# configure --toolchain=msvc needs the latter.
rm -f /usr/bin/link.exe

pacman -Sy --noconfirm --needed make nasm diffutils xz

# fetch-ffmpeg.sh retries and falls back to the GitHub mirror:
# ffmpeg.org resets from the Windows runners took out the v1.9.1
# release twice, an hour apart.
bash "$(dirname "$0")/fetch-ffmpeg.sh"
cd "ffmpeg-${FFMPEG_VERSION}"

prefix="$(cygpath -u "$GITHUB_WORKSPACE")/ffmpeg-static"

# Same minimal decode-only shape as the Linux/macOS builds, with the
# Windows GPU decode APIs (D3D11VA + the DXVA2 fallback) in place of
# VAAPI. The *_d3d11va2 hwaccels are the AV_HWDEVICE_TYPE_D3D11VA +
# hw_device_ctx path the decoder actually uses; the *_d3d11va ones are
# the legacy API, enabled alongside for completeness. -MD matches the
# /MD CRT of the plugin's Release build. The linking side lives in
# CMakeLists.txt: bcrypt/ole32/user32 resolve the static libavutil's
# RNG and DXVA2 device setup.
./configure --prefix="$prefix" --toolchain=msvc \
	--extra-cflags="-MD" \
	--disable-everything --disable-programs --disable-doc \
	--disable-avformat --disable-avfilter --disable-swscale \
	--disable-swresample --disable-avdevice --disable-network \
	--disable-debug --disable-autodetect \
	--enable-decoder=h264,hevc --enable-parser=h264,hevc \
	--enable-d3d11va --enable-dxva2 \
	--enable-hwaccel=h264_d3d11va,h264_d3d11va2,h264_dxva2 \
	--enable-hwaccel=hevc_d3d11va,hevc_d3d11va2,hevc_dxva2 \
	--disable-shared --enable-static \
	|| { tail -n 50 ffbuild/config.log; exit 1; }

make -j"$(nproc)"
make install

# The archive names configure emits have varied (libavcodec.a vs
# avcodec.lib); pin one canonical name the workflows can rely on, and
# fail loudly if neither shows up.
cd "$prefix/lib"
for lib in avcodec avutil; do
	if [ ! -f "$lib.lib" ]; then
		for cand in "lib$lib.a" "$lib.a" "lib$lib.lib"; do
			if [ -f "$cand" ]; then
				mv "$cand" "$lib.lib"
				break
			fi
		done
	fi
	[ -f "$lib.lib" ]
done
ls -l
