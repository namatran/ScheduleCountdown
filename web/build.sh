#!/bin/sh
# Copies the site into a folder ready to serve: `web/build.sh <folder>`.
# schedule.json and images/ are symlinks to files outside web/, which Vercel can't follow,
# so this copies the real files in. Vercel runs it on every push to main (see vercel.json).
set -e
OUT="$1"
cd "$(dirname "$0")"

mkdir -p "$OUT"
find "$OUT" -mindepth 1 -maxdepth 1 ! -name .vercel -exec rm -rf {} +   # keep a project link
cp -RL index.html app.js engine.js style.css briefs.txt schedule.json images mac "$OUT"/
