#!/usr/bin/env python3
"""Add the newest Bearkat Brief to web/briefs.txt, straight from the email.

Reads the school's weekly email over IMAP, finds the brief link, and opens a
pull request that adds it. It merges the PR only when the change is exactly one
new brief line, the site tests pass and every check on the PR is green.

It works in its own clone (not your working copy), so it never touches
uncommitted work.

Setup is in README.md → "Bearkat Brief automation".

    scripts/add-brief.py               # check the inbox, open the PR, merge if safe
    scripts/add-brief.py --no-merge    # stop after opening the PR
    scripts/add-brief.py --dry-run     # do everything locally, push nothing
    scripts/add-brief.py --url URL     # skip the inbox and use this link
"""

import argparse
import email
import imaplib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import date, timedelta
from email.policy import default as default_policy
from pathlib import Path

CONFIG = Path(os.environ.get("SC_BRIEF_CONFIG", "~/.config/schedulecountdown/brief.json")).expanduser()
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


def load_config():
    if not CONFIG.exists():
        raise SystemExit(f"Missing {CONFIG}. See README.md → Bearkat Brief automation.")
    config = json.loads(CONFIG.read_text())
    for key in ("imap_host", "imap_user", "sender"):
        if not config.get(key):
            raise SystemExit(f"{CONFIG} needs \"{key}\".")
    return config


def password(config):
    service = config.get("keychain_service", "schedulecountdown-brief")
    return run("security", "find-generic-password", "-s", service, "-a", config["imap_user"], "-w")


def newest_link_from_inbox(config):
    """Newest brief link in recent mail from the configured sender, or None."""
    since = (date.today() - timedelta(days=10)).strftime("%d-%b-%Y")
    mail = imaplib.IMAP4_SSL(config["imap_host"])
    try:
        mail.login(config["imap_user"], password(config))
        mail.select("INBOX", readonly=True)
        _, data = mail.search(None, "FROM", f'"{config["sender"]}"', "SINCE", since)
        found = []
        for number in data[0].split():
            _, parts = mail.fetch(number, "(RFC822)")
            message = email.message_from_bytes(parts[0][1], policy=default_policy)
            for part in message.walk():
                if part.get_content_type() in ("text/plain", "text/html"):
                    found += LINK.findall(part.get_content())
    finally:
        try:
            mail.logout()
        except Exception:
            pass
    if not found:
        return None
    week, page = max(found, key=lambda match: int(match[0]))
    return f"{BASE}brief-community-week-{week}-{page}"


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
    parser.add_argument("--url", help="use this brief link instead of reading the inbox")
    args = parser.parse_args()

    url = args.url or newest_link_from_inbox(load_config())
    if not url:
        print("No brief email in the last 10 days.")
        return
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
        "The site shows the newest 3.\n\nOpened by `scripts/add-brief.py` from the weekly email."
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
