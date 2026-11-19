#!/usr/bin/env bash
set -uo pipefail
here=$(dirname "$0")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() {
	local name=$1 tags=$2 msgs=$3 want=$4
	printf '%b' "$tags" > "$tmp/tags"
	printf '%b' "$msgs" > "$tmp/msgs"
	local got
	got=$("$here/next-version.sh" "$tmp/tags" "$tmp/msgs" 2>/dev/null | tr '\n' ' ')
	if [ "$got" = "$want " ]; then
		echo "PASS $name"
	else
		echo "FAIL $name: got [$got] want [$want]"
		fail=1
	fi
}

check "patch default" 'v1.2.3\nv1.2.2\n' 'fix thing\n' 'tag=v1.2.4 prerelease=false'
check "minor trailer" 'v1.2.3\n' 'x\n\nRelease-Bump: minor\n' 'tag=v1.3.0 prerelease=false'
check "major trailer, any case" 'v1.2.3\n' 'x\n\nrelease-bump: MAJOR\n' 'tag=v2.0.0 prerelease=false'
check "skip" 'v1.2.3\n' 'x\n\nRelease-Skip: true\n' 'tag= prerelease=false'
check "prose is ignored" 'v1.2.3\n' 'mentions Release-Skip: true in prose\n' 'tag=v1.2.4 prerelease=false'
check "last wins: bump after skip" 'v1.2.3\n' 'a\nRelease-Skip: true\nb\nRelease-Bump: minor\n' 'tag=v1.3.0 prerelease=false'
check "last wins: skip after bump" 'v1.2.3\n' 'a\nRelease-Bump: minor\nb\nRelease-Skip: true\n' 'tag= prerelease=false'
check "no tags at all" '' 'x\n' 'tag=v0.1.1 prerelease=false'
check "no stable tag, only a beta" 'v0.1.1-beta.1\n' 'x\n' 'tag=v0.1.1 prerelease=false'
check "beta numbering starts at 1" 'v1.8.1\n' 'x\nRelease-Beta: true\n' 'tag=v1.8.2-beta.1 prerelease=true'
check "beta takes first free suffix" 'v1.8.1\nv1.8.2-beta.1\nv1.8.2-beta.3\n' 'x\nRelease-Beta: true\n' 'tag=v1.8.2-beta.2 prerelease=true'
check "plain merge lands on beta base" 'v1.8.1\nv1.8.2-beta.2\n' 'x\n' 'tag=v1.8.2 prerelease=false'
check "beta floor raises stable" 'v1.9.0\nv1.10.0-beta.2\n' 'x\n' 'tag=v1.10.0 prerelease=false'
check "beta floor raises beta" 'v1.9.0\nv1.10.0-beta.1\nv1.10.0-beta.2\n' 'x\nRelease-Beta: true\n' 'tag=v1.10.0-beta.3 prerelease=true'
check "lower beta ignored" 'v1.9.0\nv1.8.0-beta.1\n' 'x\n' 'tag=v1.9.1 prerelease=false'
check "versions sort numerically" 'v1.9.0\nv1.9.5\nv1.10.0\n' 'x\n' 'tag=v1.10.1 prerelease=false'

exit $fail
