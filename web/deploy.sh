#!/bin/sh
# Publishes the site to bell.namatran.com by hand. Pushing to main does this automatically,
# so this is only a backup. Run it from anywhere: `web/deploy.sh`.
# You need to be logged in first (`vercel login`). The first run links the bell-countdown project.
set -e
cd "$(dirname "$0")"

npm test --silent
./build.sh .deploy/site

SCOPE=nam-trans-projects-771d244e
cd .deploy/site
[ -d .vercel ] || vercel link --yes --project bell-countdown --scope "$SCOPE"
vercel deploy --prod --yes --scope "$SCOPE"
