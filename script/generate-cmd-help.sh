#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

out_file='./Sources/Common/cmdHelpGenerated.swift'

hypermac_prefix="hypermac"
____usage_prefix="   USAGE:"
_______or_prefix="      OR:"
____strip_prefix="   "

triple_quote='"""'

cat << EOF > $out_file
// FILE IS GENERATED FROM docs/hypermac-*.adoc files
// TO REGENERATE THE FILE RUN generate.sh --all

EOF

for file in docs/hypermac-*.adoc; do
    subcommand=$(basename "$file" | sed 's/^hypermac-//' | sed 's/\.adoc$//' | sed 's/-/_/g')
    sed -n -E '/tag::synopsis/, /end::synopsis/ p' "$file" | \
        sed '1d' | \
        sed '$d' | \
        sed '/^$/ d' | \
        sed "1   s/^$hypermac_prefix/$____usage_prefix/" | \
        sed "2,$ s/^$hypermac_prefix/$_______or_prefix/" | \
        sed     "s/^$____strip_prefix//" | \
        sed "1 s/^/let ${subcommand}_help_generated = $triple_quote\n/" | \
        sed "\$ s/$/\n${triple_quote}/" | \
        sed '2,$ s/^/    /' >> $out_file
done
