#!/usr/bin/env bash
# Run ON THE MAC MINI. Pushes the two heavy databases up to Hetzner.
# Outbound push, so it works through home NAT with no inbound firewall rules.
#
#   ./sync-to-cloud.sh
#
# Config via env or edit the defaults below.
set -euo pipefail

# --- config -----------------------------------------------------------------
HETZNER_SSH="${HETZNER_SSH:-root@your-hetzner-host}"   # ssh target
HETZNER_DIR="${HETZNER_DIR:-/opt/bhl-workshop}"         # repo dir on Hetzner

# Local CouchDB (on the Mini) and remote CouchDB (Hetzner), with creds.
LOCAL_COUCH="${LOCAL_COUCH:-http://admin:PASS@127.0.0.1:5984}"
REMOTE_COUCH="${REMOTE_COUCH:-https://admin:PASS@couch.your-hetzner-host}"

# Local SQLite to push (bhl-name-timeline).
LOCAL_SQLITE="${LOCAL_SQLITE:-$HOME/Sites/iphylo/bhl-name-timeline/bhl.db}"

# Generated tiles/cache for bhl-all-the-pages (gitignored, so not in the clone).
LOCAL_PAGES="${LOCAL_PAGES:-$HOME/Sites/iphylo/bhl-all-the-pages}"
# ----------------------------------------------------------------------------
#
# Total upload is ~23 GB (13 GB bhl.db + 6 GB CouchDB + 4.3 GB tiles/cache).
# On a typical domestic upstream that is several hours — start days ahead.
# rsync uses --partial/--inplace, so an interrupted run resumes.

echo "== 1/3  rsync bhl.db (13 GB) -> Hetzner"
rsync -avP --inplace --partial \
  "$LOCAL_SQLITE" \
  "$HETZNER_SSH:$HETZNER_DIR/sites/bhl-name-timeline/bhl.db"

echo "== 2/3  push bhl-all-the-pages generated data (4.3 GB) -> Hetzner"
# cells.php, tiles/ and cache/ are gitignored, so bootstrap.sh's clone won't
# have them and the site won't render without this. Rebuilding on the server
# instead means re-fetching from BHL, which is far slower than pushing.
#
# This is ~545,000 tiny files (320k tiles + 225k cache). rsync is the wrong
# tool at that file count -- its per-file round-trips dominate and the transfer
# crawls. A single tar stream over ssh moves it in one pass. No -z: the tiles
# are already-compressed images, so gzip just burns CPU for nothing.
#
# Trade-off: a tar stream is NOT resumable. If it dies, re-run it. For later
# incremental top-ups (few changed files) use rsync instead:
#   rsync -a --partial "$LOCAL_PAGES"/{cells.php,tiles,cache} \
#     "$HETZNER_SSH:$HETZNER_DIR/sites/bhl-all-the-pages/"
if [[ -d "$LOCAL_PAGES/tiles" ]]; then
  ssh "$HETZNER_SSH" "mkdir -p $HETZNER_DIR/sites/bhl-all-the-pages"
  tar -C "$LOCAL_PAGES" -cf - cells.php tiles cache \
    | ssh "$HETZNER_SSH" "tar -C $HETZNER_DIR/sites/bhl-all-the-pages -xf -"
else
  echo "   (skipping -- no tiles/ found at $LOCAL_PAGES)"
fi

echo "== 3/3  set up CONTINUOUS CouchDB replication (Mini -> Hetzner)"
# A persistent doc in _replicator survives restarts and keeps the backup live.
curl -sS -X PUT "$LOCAL_COUCH/_replicator/bhl-lite-to-cloud" \
  -H 'Content-Type: application/json' \
  -d "{
        \"_id\": \"bhl-lite-to-cloud\",
        \"source\": \"bhl-lite\",
        \"target\": \"$REMOTE_COUCH/bhl-lite\",
        \"create_target\": true,
        \"continuous\": true
      }" && echo

echo
echo "Done. Check replication status:"
echo "  curl -s $LOCAL_COUCH/_scheduler/docs/_replicator/bhl-lite-to-cloud | python3 -m json.tool"
