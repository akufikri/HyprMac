#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Check if documentation source files exist
if ! ls docs/*.adoc > /dev/null 2>&1; then
    echo "⚠️  No documentation source files found in docs/*.adoc"
    echo "Skipping documentation build..."

    # Create empty directories so the build doesn't fail
    rm -rf .site && mkdir .site
    rm -rf .man && mkdir .man

    # Create minimal placeholder man page
    mkdir -p .man
    echo ".TH HYPERMAC 1 \"$(date +%Y-%m-%d)\" \"HyperMac\" \"User Commands\"" > .man/hypermac.1
    echo ".SH NAME" >> .man/hypermac.1
    echo "hypermac \\- Hyprland-inspired tiling window manager for macOS" >> .man/hypermac.1
    echo ".SH DESCRIPTION" >> .man/hypermac.1
    echo "See https://github.com/BarutSRB/HyprSpace for documentation" >> .man/hypermac.1

    exit 0
fi

./script/install-dep.sh --bundler

rm -rf .site && mkdir .site
rm -rf .man && mkdir .man

cp-docs() {
    cp -r ./docs/*.adoc "$1"
    if test -d ./docs/assets; then
        cp -r ./docs/assets "$1"
    fi
    if test -d ./docs/util; then
        cp -r ./docs/util "$1"
    fi
    cp -r ./docs/config-examples "$1"
}

build-site() {
    cp-docs ./.site
    if test -f ./docs/index.html; then
        cp ./docs/index.html ./.site
    fi

    cd .site
        # Delete "hypermac " prefifx in synopsis
        sed -E -i '' '/tag::synopsis/, /end::synopsis/ s/^(hypermac | {10})//' hypermac* 2>/dev/null || true
        bundler exec asciidoctor ./guide.adoc ./commands.adoc ./goodies.adoc 2>/dev/null || true
        if test -f goodies.html; then
            cp goodies.html goodness.html # backwards compatibility
        fi
        rm -rf ./*.adoc
    cd - > /dev/null

    git rev-parse HEAD > .site/version.html
    if ! test -z "$(git status --porcelain)"; then
        echo "git working directory is dirty" >> .site/version.html
    fi
}

build-man() {
    cp-docs .man
    cd .man
        bundler exec asciidoctor -b manpage hypermac*.adoc
        rm -rf -- *.adoc
    cd - > /dev/null
}

build-site
build-man
