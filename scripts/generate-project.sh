#!/bin/sh
# Regenerates Orio.xcodeproj from project.yml and mirrors it into NapsafeWatch.xcodeproj,
# which the Xcode Cloud workflow still builds until it is repointed to Orio.xcodeproj.
set -eu

cd "$(dirname "$0")/.."

xcodegen generate
xcodegen generate --only-plists

alias_project=NapsafeWatch.xcodeproj
schemes_dir="$alias_project/xcshareddata/xcschemes"

mkdir -p "$schemes_dir" "$alias_project/project.xcworkspace"
cp Orio.xcodeproj/project.pbxproj "$alias_project/project.pbxproj"
cp Orio.xcodeproj/project.xcworkspace/contents.xcworkspacedata "$alias_project/project.xcworkspace/contents.xcworkspacedata"
for scheme in Orio NapsafeWatch; do
    sed 's/container:Orio\.xcodeproj/container:NapsafeWatch.xcodeproj/' \
        Orio.xcodeproj/xcshareddata/xcschemes/Orio.xcscheme > "$schemes_dir/$scheme.xcscheme"
done
