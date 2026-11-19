#!/usr/bin/env python3
"""Add a Bearkat Brief link to web/briefs.txt and open a pull request.

    scripts/add-brief.py --url LINK              # add it, open the PR, merge if safe
    scripts/add-brief.py --url LINK --no-merge   # stop after opening the PR
    scripts/add-brief.py --url LINK --dry-run    # do everything locally, push nothing

It merges the PR only when the change is exactly one new brief line, the site
tests pass and every check on the PR is green. Needs `gh` logged in.

It works in its own clone (not your working copy), so it never touches
uncommitted work.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

CLONE = Path(os.environ.get("SC_BRIEF_CLONE", "~/.cache/schedulecountdown-brief")).expanduser()
REPO = "namatran/ScheduleCountdown"

BASE = "https://kleinisd.edurooms.com/newsletters/klein-high-school/newsletters/"
LINK = re.compile(re.escape(BASE) + r"brief-community-week-(\d+)-(\d+)")


def run(*cmd, cwd=None, capture=True):
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=capture)
    if result.returncode != 0:
        raise SystemExit(f"`{' '.join(cmd)}` failed:\n{result.stderr or result.stdout}")
    return (result.stdout or "").strip()


def notify(message):
    print(message)
    subprocess.run(
        ["osascript", "-e", f'display notification {json.dumps(message)} with title "Bearkat Brief"'],
        capture_output=True,
    )


def page_is_brief(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=20) as response:
        html = response.read().decode("utf-8", "replace")
    return response.status == 200 and "<title>Brief" in html


def sync_clone():
    if not (CLONE / ".git").exists():
        CLONE.parent.mkdir(parents=True, exist_ok=True)
        run("gh", "repo", "clone", REPO, str(CLONE))
    run("git", "fetch", "-q", "origin", cwd=CLONE)
    run("git", "checkout", "-q", "--detach", "origin/main", cwd=CLONE)


def checks_state(pr):
    """'pass', 'fail' or 'wait' for every check on the PR."""
    out = run("gh", "pr", "view", pr, "--repo", REPO, "--json", "statusCheckRollup")
    checks = json.loads(out)["statusCheckRollup"]
    if not checks:
        return "wait"
    states = [(c.get("conclusion") or c.get("state") or "").upper() for c in checks]
    if any(s in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT") for s in states):
        return "fail"
    if all(s in ("SUCCESS", "NEUTRAL", "SKIPPED") for s in states):
        return "pass"
    return "wait"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="commit locally, push nothing")
    parser.add_argument("--no-merge", action="store_true", help="open the PR but leave it for you to merge")
    parser.add_argument("--url", required=True, help="the Bearkat Brief link")
    args = parser.parse_args()

    url = args.url.strip()
    match = LINK.fullmatch(url)
    if not match:
        raise SystemExit(f"Not a brief link: {url}")
    week = int(match.group(1))

    sync_clone()
    briefs = CLONE / "web" / "briefs.txt"
    text = briefs.read_text()
    if re.search(rf"brief-community-week-{week}-", text):
        print(f"Week {week} is already in briefs.txt.")
        return
    if not page_is_brief(url):
        raise SystemExit(f"{url} didn't load as a Bearkat Brief page.")

    branch = f"web/brief-week-{week}"
    if run("git", "ls-remote", "--heads", "origin", branch, cwd=CLONE):
        print(f"{branch} is already on GitHub; leaving it alone.")
        return

    run("git", "checkout", "-q", "-B", branch, "origin/main", cwd=CLONE)
    lines = text.splitlines()
    briefs.write_text("\n".join(lines[:1] + [url] + lines[1:]) + "\n")
    diff = run("git", "diff", "--numstat", cwd=CLONE).split("\n")
    if diff != ["1\t0\tweb/briefs.txt"]:
        raise SystemExit(f"Unexpected change, stopping:\n{run('git', 'diff', cwd=CLONE)}")
    run("npm", "test", cwd=CLONE / "web")
    run("git", "add", "web/briefs.txt", cwd=CLONE)
    run("git", "commit", "-q", "-m", f"feat(web): add bearkat brief week {week}", cwd=CLONE)

    if args.dry_run:
        print(f"Dry run: committed week {week} on {branch} in {CLONE}; nothing pushed.")
        return

    run("git", "push", "-q", "-u", "origin", branch, cwd=CLONE)
    body = (
        f"Adds the week {week} Bearkat Brief link to the top of `web/briefs.txt`. "
        "The site shows the newest 3.\n\nOpened by `scripts/add-brief.py`."
    )
    pr = run(
        "gh", "pr", "create", "--repo", REPO, "--base", "main", "--head", branch,
        "--title", f"feat(web): add bearkat brief week {week}", "--body", body,
    )
    if args.no_merge:
        notify(f"Week {week} brief PR is open. Check the preview, then merge it.")
        return

    # Merge only once every check (Vercel preview, tests) is green.
    for _ in range(40):
        state = checks_state(pr)
        if state != "wait":
            break
        time.sleep(30)
    if state != "pass":
        notify(f"Week {week} brief PR is open but not merged: checks {'failed' if state == 'fail' else 'are still running'}.")
        return
    run("gh", "pr", "merge", pr, "--repo", REPO, "--merge", "--delete-branch")
    notify(f"Week {week} brief is live on khsbell.com.")


if __name__ == "__main__":
    sys.exit(main())
