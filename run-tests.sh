#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./build-debug.sh
./run-swift-test.sh

./.debug/hypermac -h > /dev/null
./.debug/hypermac --help > /dev/null
./.debug/hypermac -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/hypermac --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./format.sh
./generate.sh --all
./script/check-uncommitted-files.sh

echo
echo "All tests have passed successfully"
