#!/bin/zsh
# Builds HAApp, packs it as a .dmg and a .zip, and publishes both as a GitHub Release people can download.
# The app is signed ad hoc (no Apple Developer account), so macOS asks people
# to allow it on first open; the release notes explain how.
#
# Usage: tools/release.sh 1.0.0            build, tag v1.0.0, push the tag, publish the release
#        tools/release.sh 1.0.0 --dry-run  build the dmg and zip only; nothing is tagged or published
#
# Needs: a clean git tree, a GitHub remote, and `gh auth login`.
set -euo pipefail
here=${0:A:h:h}
name="HAApp"
version="${1:-}"
dry=0
[[ " $* " == *" --dry-run "* ]] && dry=1

[[ "$version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || { echo "usage: tools/release.sh <version, like 1.0.0> [--dry-run]"; exit 1; }
tag="v$version"
cd "$here"

if (( ! dry )); then
  [[ -z "$(git status --porcelain)" ]] || { echo "commit or set aside your changes first"; exit 1; }
  gh repo view >/dev/null 2>&1 || { echo "no GitHub repo for this folder: create one with 'gh repo create' and push first"; exit 1; }
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "tag $tag already exists"; exit 1; }
  # The app checks this repo for updates (HAApp > Check for Updates…).
  export APP_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi

out="$here/.build/release-$version"
rm -rf "$out"
mkdir -p "$out"
APP_DIR="$out" APP_VERSION="$version" SIGN_IDENTITY=- "$here/build.sh"

zip="$out/$name-$version.zip"
# ditto keeps the bundle's symlinks, permissions, and signature intact; plain zip doesn't.
ditto -c -k --sequesterRsrc --keepParent "$out/$name.app" "$zip"
codesign --verify --deep --strict "$out/$name.app"
echo "built $zip ($(du -h "$zip" | cut -f1))"

# The disk image shows the app next to an Applications shortcut, so people drag one onto the other.
dmg="$out/$name-$version.dmg"
stage="$out/dmg"
mkdir -p "$stage"
ditto "$out/$name.app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "$name $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$stage"
hdiutil verify -quiet "$dmg"
echo "built $dmg ($(du -h "$dmg" | cut -f1))"

notes="$out/notes.md"
cat > "$notes" <<EOF
## Install

1. Download **$name-$version.dmg** below and open it. (Or download **$name-$version.zip**, if you prefer.)
2. Drag **$name.app** onto the **Applications** folder.
3. Open it. macOS says it can't check the app for malicious software, because it isn't notarized by Apple.
   Go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to $name.

   Or run this once in Terminal: \`xattr -dr com.apple.quarantine /Applications/$name.app\`

Needs macOS 26 or later on a Mac with Apple silicon.
EOF

if (( dry )); then
  echo "dry run: nothing tagged or published. Release notes: $notes"
  exit 0
fi

git tag -a "$tag" -m "$name $version"
git push origin "$tag"
gh release create "$tag" "$dmg" "$zip" --title "$name $version" --notes-file "$notes"
