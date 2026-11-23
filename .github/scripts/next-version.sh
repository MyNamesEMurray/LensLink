#!/usr/bin/env bash
set -euo pipefail

tags=$(cat "$1")
messages=$(cat "$2")

# Only stable tags seed the next number: version sort puts a pre-release
# above the version it precedes, and "0-beta.2" breaks the arithmetic below.
latest=$(grep -xE 'v[0-9]+\.[0-9]+\.[0-9]+' <<< "$tags" | sort -rV | head -1 || true)
latest=${latest:-v0.1.0}
IFS=. read -r major minor patch <<< "${latest#v}"

# Directives are read oldest first and the LAST one wins: a later commit
# revises an earlier one in either direction. Trailers only match on their
# own line, so prose mentioning the keywords is ignored.
skip=false
bump=patch
beta=false
shopt -s nocasematch
while IFS= read -r line; do
	if [[ $line =~ ^Release-Skip:[[:space:]]*true[[:space:]]*$ ]]; then
		skip=true
	elif [[ $line =~ ^Release-Bump:[[:space:]]*(major|minor|patch)[[:space:]]*$ ]]; then
		bump=${BASH_REMATCH[1],,}; skip=false
	elif [[ $line =~ ^Release-Beta:[[:space:]]*true[[:space:]]*$ ]]; then
		beta=true; skip=false
	fi
done <<< "$messages"
shopt -u nocasematch

if [ "$skip" = true ]; then
	echo "tag="
	echo "prerelease=false"
	exit 0
fi

case "$bump" in
	major) major=$((major + 1)); minor=0; patch=0 ;;
	minor) minor=$((minor + 1)); patch=0 ;;
	*)     patch=$((patch + 1)) ;;
esac
tag="v$major.$minor.$patch"

# An in-flight beta line outranks a lower computed version, so testers
# never watch the version go backwards (v1.10.0-beta.2 vs a plain v1.9.2).
# Bases are compared with sort -V after stripping the suffix.
pre_base=$(grep -xE 'v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+' <<< "$tags" \
           | sed -E 's/-beta\.[0-9]+$//' | sort -uV | tail -1 || true)
if [ -n "$pre_base" ] && [ "$pre_base" != "$tag" ] \
   && [ "$(printf '%s\n%s\n' "$tag" "$pre_base" | sort -V | tail -1)" = "$pre_base" ]; then
	echo "::notice::$tag would land below the in-flight $pre_base beta line; releasing $pre_base instead." >&2
	tag="$pre_base"
fi

# Beta: probe for the first free suffix rather than counting, so numbering
# stays right if a beta tag was deleted by hand.
if [ "$beta" = true ]; then
	n=1
	while grep -qxF "$tag-beta.$n" <<< "$tags"; do
		n=$((n + 1))
	done
	echo "tag=$tag-beta.$n"
	echo "prerelease=true"
else
	echo "tag=$tag"
	echo "prerelease=false"
fi
