#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/check-uncommitted-files.sh

rm -rf ~/Library/Developer/Xcode/DerivedData/HyperMac-*
rm -rf ./.xcode-build

rm -rf HyperMac.xcodeproj
./generate.sh
