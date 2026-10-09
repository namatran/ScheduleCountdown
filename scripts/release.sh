#!/bin/bash
# Two-step release. Never pushes; publishing to GitHub only happens after you confirm.
#
#   scripts/release.sh <version> [--critical]   bump, package, sign, build dist/appcast.xml, commit
#   git push                                    (you)
#   scripts/release.sh --publish <version>      create the GitHub Release (dmg, zip, appcast)
#
# The release notes are the version's section in CHANGELOG.md. If it's missing, the first run
# drafts one from the commits since the last release and stops so you can rewrite it.
# --critical makes Sparkle hide "Skip This Version" and "Remind Me Later" for this update.
#
# The Sparkle EdDSA private key must be in the login Keychain (see README → Releasing).
set -euo pipefail
cd "$(dirname "$0")/.."

repo=namatran/ScheduleCountdown
zip=dist/ScheduleCountdown.zip
dmg=dist/ScheduleCountdown.dmg
appcast=dist/appcast.xml
notes=dist/release-notes.md
checksum=dist/release.sha256
app=build/Build/Products/Release/ScheduleCountdown.app
sparkle_bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin

die() { echo "error: $*" >&2; exit 1; }
usage() { die "usage: $0 <version> [--critical]  |  $0 --publish <version>"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
setting() { sed -n "s/^ *$1: \"\(.*\)\"$/\1/p" project.yml; }

# The bullets under "## <version>" (dated or not) in CHANGELOG.md.
changelog_section() {
    awk -v v="$1" '
        /^## / { inside = ($0 == "## " v || index($0, "## " v " — ") == 1); next }
        inside && NF { print }
    ' CHANGELOG.md
}

# Adds a "## <version>" section above the newest one, drafted from feat/fix commit subjects.
draft_changelog() {
    local version=$1 last_tag range section updated
    last_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
    range=${last_tag:+$last_tag..}HEAD
    section=$(mktemp); updated=$(mktemp)
    { printf '## %s\n\n' "$version"
      git log --reverse --format=%s "$range" \
          | sed -n -E 's/^(feat|fix|perf)(\([^)]*\))?!?: (.*)$/\3/p' \
          | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) "." }
                 END { if (!NR) print "- " }'
      echo; } > "$section"
    awk -v section="$section" '
        function insert() { while ((getline line < section) > 0) print line; done = 1 }
        /^## / && !done { insert() }
        { print }
        END { if (!done) { print ""; insert() } }
    ' CHANGELOG.md > "$updated"
    mv "$updated" CHANGELOG.md
    rm -f "$section"
    echo "Drafted a $version section in CHANGELOG.md from the commits since ${last_tag:-the start}."
}

prepare() {
    local version=$1 critical=$2

    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3"
    # Your CHANGELOG.md edits for this release may be uncommitted; they go in the bump commit.
    [[ -z $(git status --porcelain | grep -v ' CHANGELOG.md$') ]] || die "working tree isn't clean"
    [[ $(git branch --show-current) == main ]] || die "not on main"
    # Tags too: --publish creates them on GitHub, and the changelog draft starts at the last one.
    git fetch --quiet --tags origin main
    [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main isn't in sync with origin/main"
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
    if git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
        || [[ -n $(git ls-remote --tags origin "v$version") ]]; then
        die "tag v$version already exists"
    fi

    local old_version old_build build
    old_version=$(setting MARKETING_VERSION)
    old_build=$(setting CURRENT_PROJECT_VERSION)
    [[ $(printf '%s\n%s\n' "$old_version" "$version" | sort -V | tail -1) == "$version" \
        && $version != "$old_version" ]] || die "$version isn't newer than $old_version"
    build=$((old_build + 1))

    if ! grep -q -E "^## $version( —|$)" CHANGELOG.md; then
        draft_changelog "$version"
        die "rewrite the $version section of CHANGELOG.md for students, then rerun $0 $version"
    fi
    [[ -n $(changelog_section "$version" | grep -E '^- .*[^ ]') ]] \
        || die "the $version section of CHANGELOG.md has no notes"

    echo "==> Dating CHANGELOG.md and bumping $old_version ($old_build) → $version ($build)"
    sed -i '' -E "s/^## $version( — .*)?$/## $version — $(date +%Y-%m-%d)/" CHANGELOG.md
    sed -i '' -e "s/^\( *MARKETING_VERSION:\) \".*\"$/\1 \"$version\"/" \
              -e "s/^\( *CURRENT_PROJECT_VERSION:\) \".*\"$/\1 \"$build\"/" project.yml

    echo "==> Packaging"
    scripts/package.sh
    [[ $(plist CFBundleShortVersionString) == "$version" && $(plist CFBundleVersion) == "$build" ]] \
        || die "built app has the wrong version"

    echo "==> Signing $zip"
    local signature
    signature=$("$sparkle_bin/sign_update" "$zip")   # sparkle:edSignature="…" length="…"

    # GitHub shows the Markdown; Sparkle's window shows plain text, so use • bullets there.
    { changelog_section "$version"
      cat <<EOF

---
**New install?** Download **ScheduleCountdown.dmg** below, open it, and drag the app into Applications. The first time you open it, macOS blocks it because the app isn't from a paid Apple developer account; that's expected. Click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**. You only do this once, and updates install on their own after that.

<img src="https://raw.githubusercontent.com/$repo/main/docs/images/open-anyway.png" width="600" alt="Privacy & Security settings with the Open Anyway button for ScheduleCountdown">
EOF
    } > "$notes"
    local plain_notes
    plain_notes=$(changelog_section "$version" | awk '
        /^- / { if (n++) printf "\n"; printf "• %s", substr($0, 3); next }
        { sub(/^ +/, ""); printf " %s", $0 }')

    echo "==> Writing $appcast"
    local item previous
    item=$(mktemp); previous=$(mktemp -d)
    cat > "$item" <<EOF
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(plist LSMinimumSystemVersion)</sparkle:minimumSystemVersion>$(
        [[ $critical == yes ]] && printf '\n      <sparkle:criticalUpdate></sparkle:criticalUpdate>')
      <description sparkle:format="plain-text"><![CDATA[$plain_notes]]></description>
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
    shasum -a 256 "$zip" "$dmg" "$appcast" "$notes" > "$checksum"

    git add project.yml CHANGELOG.md
    git commit -q -m "chore(release): bump version to $version"

    cat <<EOF

Prepared v$version (build $build)$([[ $critical == yes ]] && echo ", critical"): $dmg, $zip, $appcast.
Committed the version bump and dated changelog locally. Next:
  1. git push
  2. scripts/release.sh --publish $version
EOF
}

publish() {
    local version=$1 sha
    for f in "$zip" "$dmg" "$appcast" "$notes" "$checksum"; do
        [[ -f $f ]] || die "$f missing; run $0 $version first"
    done
    shasum -a 256 -c --quiet "$checksum" || die "dist/ changed since it was prepared; rerun $0 $version"
    grep -q "<sparkle:shortVersionString>$version<" "$appcast" || die "$appcast isn't for $version"
    [[ $(git log -1 --format=%s) == "chore(release): bump version to $version" ]] \
        || die "HEAD isn't the $version bump commit"
    git fetch --quiet origin main
    git merge-base --is-ancestor HEAD origin/main || die "HEAD isn't pushed to origin/main yet (git push)"
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
    sha=$(git rev-parse HEAD)

    local critical=no
    # Only the newest item counts; older ones in the appcast may have been critical.
    awk '/<item>/ { n++ } n == 1' "$appcast" | grep -q criticalUpdate && critical=yes
    cat <<EOF
About to publish a GitHub Release on $repo:
  tag       v$version → $sha
  assets    $dmg ($(du -h "$dmg" | cut -f1 | xargs)), $zip ($(du -h "$zip" | cut -f1 | xargs)), $appcast
  critical  $critical
  notes:
$(sed 's/^/    /' "$notes")
Every installed copy will be offered this update.
EOF
    read -r -p "Publish v$version to GitHub? [y/N] " answer < /dev/tty
    [[ $answer == [yY] ]] || { echo "Not published."; exit 1; }

    gh release create "v$version" "$dmg" "$zip" "$appcast" --repo "$repo" --target "$sha" \
        --title "ScheduleCountdown $version" --notes-file "$notes"
}

case "${1:-}" in
    --publish) [[ $# -eq 2 ]] || usage; publish "$2" ;;
    ""|-*) usage ;;
    *)
        version=$1; shift; critical=no
        if [[ $# -gt 0 ]]; then [[ $1 == --critical && $# -eq 1 ]] || usage; critical=yes; fi
        prepare "$version" "$critical" ;;
esac
