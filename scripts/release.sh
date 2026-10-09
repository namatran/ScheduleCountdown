#!/bin/bash
# Two-step release. Never pushes; publishing to GitHub only happens after you confirm.
#
#   scripts/release.sh <version> [--notes <file>]   bump, package, sign, build dist/appcast.xml, commit
#   git push                                        (you)
#   scripts/release.sh --publish <version>          create the GitHub Release with the zip + appcast
#
# The Sparkle EdDSA private key must be in the login Keychain (see README → Releasing).
set -euo pipefail
cd "$(dirname "$0")/.."

repo=namatran/ScheduleCountdown
zip=dist/ScheduleCountdown.zip
appcast=dist/appcast.xml
notes=dist/release-notes.txt
checksum=dist/release.sha256
app=build/Build/Products/Release/ScheduleCountdown.app
sparkle_bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin

die() { echo "error: $*" >&2; exit 1; }
usage() { die "usage: $0 <version> [--notes <file>]  |  $0 --publish <version>"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
setting() { sed -n "s/^ *$1: \"\(.*\)\"$/\1/p" project.yml; }

prepare() {
    local version=$1 notes_file=$2

    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3"
    [[ -z $(git status --porcelain) ]] || die "working tree isn't clean"
    [[ $(git branch --show-current) == main ]] || die "not on main"
    git fetch --quiet origin main
    [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main isn't in sync with origin/main"
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
    if git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
        || [[ -n $(git ls-remote --tags origin "v$version") ]]; then
        die "tag v$version already exists"
    fi
    [[ -z $notes_file || -f $notes_file ]] || die "notes file not found: $notes_file"

    local old_version old_build build
    old_version=$(setting MARKETING_VERSION)
    old_build=$(setting CURRENT_PROJECT_VERSION)
    [[ $(printf '%s\n%s\n' "$old_version" "$version" | sort -V | tail -1) == "$version" \
        && $version != "$old_version" ]] || die "$version isn't newer than $old_version"
    build=$((old_build + 1))

    echo "==> Bumping $old_version ($old_build) → $version ($build)"
    sed -i '' -e "s/^\( *MARKETING_VERSION:\) \".*\"$/\1 \"$version\"/" \
              -e "s/^\( *CURRENT_PROJECT_VERSION:\) \".*\"$/\1 \"$build\"/" project.yml

    echo "==> Packaging"
    scripts/package.sh
    [[ $(plist CFBundleShortVersionString) == "$version" && $(plist CFBundleVersion) == "$build" ]] \
        || die "built app has the wrong version"

    echo "==> Signing $zip"
    local signature
    signature=$("$sparkle_bin/sign_update" "$zip")   # sparkle:edSignature="…" length="…"

    if [[ -n $notes_file ]]; then cp "$notes_file" "$notes"; else echo "ScheduleCountdown $version" > "$notes"; fi

    echo "==> Writing $appcast"
    local item previous
    item=$(mktemp); previous=$(mktemp -d)
    cat > "$item" <<EOF
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(plist LSMinimumSystemVersion)</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text"><![CDATA[$(cat "$notes")]]></description>
      <enclosure url="https://github.com/$repo/releases/download/v$version/ScheduleCountdown.zip" type="application/octet-stream" $signature/>
    </item>
EOF
    # Keep earlier items: start from the appcast attached to the latest release, if any.
    if gh release download --repo "$repo" --pattern appcast.xml --dir "$previous" 2>/dev/null; then
        awk -v item="$item" '{ print } /<title>ScheduleCountdown<\/title>/ && !done { while ((getline line < item) > 0) print line; done = 1 }' \
            "$previous/appcast.xml" > "$appcast"
    else
        { cat <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ScheduleCountdown</title>
EOF
          cat "$item"
          printf '  </channel>\n</rss>\n'; } > "$appcast"
    fi
    rm -rf "$item" "$previous"
    xmllint --noout "$appcast"
    grep -q "<sparkle:version>$build<" "$appcast" || die "new item missing from $appcast"
    shasum -a 256 "$zip" "$appcast" > "$checksum"

    git add project.yml
    git commit -q -m "chore(release): bump version to $version"

    cat <<EOF

Prepared v$version (build $build): $zip, $appcast, $notes.
Committed the version bump locally. Next:
  1. git push
  2. scripts/release.sh --publish $version
EOF
}

publish() {
    local version=$1 sha
    for f in "$zip" "$appcast" "$notes" "$checksum"; do [[ -f $f ]] || die "$f missing; run $0 $version first"; done
    shasum -a 256 -c --quiet "$checksum" || die "dist/ changed since it was prepared; rerun $0 $version"
    grep -q "<sparkle:shortVersionString>$version<" "$appcast" || die "$appcast isn't for $version"
    [[ $(git log -1 --format=%s) == "chore(release): bump version to $version" ]] \
        || die "HEAD isn't the $version bump commit"
    git fetch --quiet origin main
    git merge-base --is-ancestor HEAD origin/main || die "HEAD isn't pushed to origin/main yet (git push)"
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
    sha=$(git rev-parse HEAD)

    cat <<EOF
About to publish a GitHub Release on $repo:
  tag     v$version → $sha
  assets  $zip ($(du -h "$zip" | cut -f1 | xargs)), $appcast
  notes   $(head -1 "$notes")
Every installed copy will be offered this update.
EOF
    read -r -p "Publish v$version to GitHub? [y/N] " answer < /dev/tty
    [[ $answer == [yY] ]] || { echo "Not published."; exit 1; }

    gh release create "v$version" "$zip" "$appcast" --repo "$repo" --target "$sha" \
        --title "ScheduleCountdown $version" --notes-file "$notes"
}

case "${1:-}" in
    --publish) [[ $# -eq 2 ]] || usage; publish "$2" ;;
    ""|-*) usage ;;
    *)
        version=$1; shift; notes_file=""
        if [[ $# -gt 0 ]]; then [[ $1 == --notes && $# -eq 2 ]] || usage; notes_file=$2; fi
        prepare "$version" "$notes_file" ;;
esac
