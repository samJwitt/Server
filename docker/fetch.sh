#!/bin/sh
# fetch <repo url> <commit> <dir> - shallow-fetch one commit, then apply patches/<dir>/*.patch
set -e

url="$1"
ref="$2"
dir="$3"

git init -q "$dir"
git -C "$dir" fetch -q --depth 1 "$url" "$ref"
git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD

for patch in /patches/"$dir"/*.patch; do
    [ -e "$patch" ] || continue
    echo "applying $patch"
    git -C "$dir" -c user.name=build -c user.email=build@localhost am -q "$patch"
done
