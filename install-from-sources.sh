#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

rebuild=1
while test $# -gt 0; do
    case $1 in
        --dont-rebuild) rebuild=0; shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

if test $rebuild == 1; then
    ./build-release.sh
fi

brew list hypermac-dev > /dev/null 2>&1 && brew uninstall hypermac-dev
brew list hypermac > /dev/null 2>&1 && brew uninstall hypermac

# Override HOMEBREW_CACHE. Otherwise, homebrew refuses to "redownload" the snapshot file
# Maybe there is a better way, I don't know
rm -rf /tmp/hypermac-from-sources-brew-cache
env HOMEBREW_CACHE=/tmp/hypermac-from-sources-brew-cache brew install --cask ./.release/hypermac-dev.rb
