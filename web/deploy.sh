#!/bin/sh
# Publishes the site to bell.namatran.com. Run it from anywhere: `web/deploy.sh`.
# schedule.json and images/ are symlinks to files outside web/, which Vercel can't follow,
# so this copies the site into .deploy/site (with the real files) and deploys that folder.
# You need to be logged in first (`vercel login`). The first run links the bell-countdown project.
set -e
cd "$(dirname "$0")"

npm test --silent

mkdir -p .deploy/site
find .deploy/site -mindepth 1 -maxdepth 1 ! -name .vercel -exec rm -rf {} +   # keep the project link
cp -RL index.html app.js engine.js style.css briefs.txt schedule.json images mac .deploy/site/

SCOPE=nam-trans-projects-771d244e
cd .deploy/site
[ -d .vercel ] || vercel link --yes --project bell-countdown --scope "$SCOPE"
vercel deploy --prod --yes --scope "$SCOPE"
