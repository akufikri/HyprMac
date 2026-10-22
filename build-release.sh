#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="hypermac-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

generate-git-hash() {
cat > Sources/Common/gitHashGenerated.swift <<EOF
public let gitHash = "$(git rev-parse HEAD)"
public let gitShortHash = "$(git rev-parse --short HEAD)"
EOF
}

#############
### BUILD ###
#############

./build-docs.sh
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity"

generate-git-hash
swift build -c release --arch arm64 --arch x86_64 --product hypermac # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme HyperMac \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/HyperMac.app" .release
cp -r .build/apple/Products/Release/hypermac .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/hypermac

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/HyperMac.app
.release/HyperMac.app/Contents
.release/HyperMac.app/Contents/_CodeSignature
.release/HyperMac.app/Contents/_CodeSignature/CodeResources
.release/HyperMac.app/Contents/MacOS
.release/HyperMac.app/Contents/MacOS/HyperMac
.release/HyperMac.app/Contents/Resources
.release/HyperMac.app/Contents/Resources/default-config.toml
.release/HyperMac.app/Contents/Resources/AppIcon.icns
.release/HyperMac.app/Contents/Resources/Assets.car
.release/HyperMac.app/Contents/Info.plist
.release/HyperMac.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/HyperMac.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/HyperMac.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/HyperMac.app/Contents/MacOS/HyperMac
check-universal-binary .release/hypermac

check-contains-hash .release/HyperMac.app/Contents/MacOS/HyperMac
check-contains-hash .release/hypermac

codesign -v .release/HyperMac.app
codesign -v .release/hypermac

############
### PACK ###
############

mkdir -p ".release/HyperMac-v$build_version/manpage" && cp .man/*.1 ".release/HyperMac-v$build_version/manpage"
cp -r ./legal ".release/HyperMac-v$build_version/legal"
cp -r .shell-completion ".release/HyperMac-v$build_version/shell-completion"
cd .release
    mkdir -p "HyperMac-v$build_version/bin" && cp -r hypermac "HyperMac-v$build_version/bin"
    cp -r HyperMac.app "HyperMac-v$build_version"
    zip -r "HyperMac-v$build_version.zip" "HyperMac-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in hypermac hypermac-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --app-bundle-dir-name "HyperMac.app" \
        --zip-uri ".release/HyperMac-v$build_version.zip" \
        --build-version "$build_version"
done
