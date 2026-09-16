#!/usr/bin/env bash
# Run ON THE MAC MINI. Pushes the two heavy databases up to Hetzner.
# Outbound push, so it works through home NAT with no inbound firewall rules.
#
#   ./sync-to-cloud.sh
#
# Config via env or edit the defaults below.
set -euo pipefail

# --- config -----------------------------------------------------------------
# 'bhl-hetzner' is an ssh alias defined in ~/.ssh/config on the Mini (HostName,
# User and the id_ed25519_hetzner IdentityFile live there, not here).
HETZNER_SSH="${HETZNER_SSH:-bhl-hetzner}"                    # ssh target
# NB: this is the deploy/ dir inside the cloned repo -- that is where
# bootstrap.sh creates sites/, not the repo root.
HETZNER_DIR="${HETZNER_DIR:-/opt/bhl-workshop/deploy}"       # deploy dir on Hetzner

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
ssh "$HETZNER_SSH" "mkdir -p $HETZNER_DIR/sites/bhl-name-timeline"
rsync -avP --inplace --partial \
  "$LOCAL_SQLITE" \
  "$HETZNER_SSH:$HETZNER_DIR/sites/bhl-name-timeline/bhl.db"

echo "== 2/3  push bhl-all-the-pages generated data (4.3 GB) -> Hetzner"
# cells.php, config.php, tiles/ and cache/ are gitignored, so bootstrap.sh's clone won't
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
  tar -C "$LOCAL_PAGES" -cf - cells.php config.php tiles cache \
    | ssh "$HETZNER_SSH" "tar -C $HETZNER_DIR/sites/bhl-all-the-pages -xf -"
else
  echo "   (skipping -- no tiles/ found at $LOCAL_PAGES)"
fi

echo "== 3/3  set up CONTINUOUS CouchDB replication (Mini -> Hetzner)"
# CouchDB 3.x removed local endpoints: BOTH source and target must be full URLs
# (a bare "bhl-lite" gets 403 local_endpoints_not_supported), and _replicator
# has to exist on this machine first -- a fresh CouchDB does not create it.
for db in _users _replicator _global_changes; do
  curl -s -o /dev/null -X PUT "$LOCAL_COUCH/$db" || true
done

# A persistent doc in _replicator survives restarts and keeps the copy live.
rep_body=$(mktemp)
rep_code=$(curl -s -o "$rep_body" -w '%{http_code}' -X PUT \
  "$LOCAL_COUCH/_replicator/bhl-lite-to-cloud" \
  -H 'Content-Type: application/json' \
  -d "{
        \"_id\": \"bhl-lite-to-cloud\",
        \"source\": \"$LOCAL_COUCH/bhl-lite\",
        \"target\": \"$REMOTE_COUCH/bhl-lite\",
        \"create_target\": true,
        \"continuous\": true
      }")

case "$rep_code" in
  20*) echo "   replication doc installed (HTTP $rep_code)" ;;
  409) echo "   replication doc already exists (HTTP 409) -- leaving it alone" ;;
  *)   # Never print the raw body: the URLs in it carry credentials.
       echo "!! replication FAILED (HTTP $rep_code):" >&2
       sed -E 's#://[^@]*@#://***:***@#g' "$rep_body" >&2; echo >&2
       rm -f "$rep_body"; exit 1 ;;
esac
rm -f "$rep_body"

echo
echo "Done. Check replication status with:"
echo '  curl -s "$LOCAL_COUCH/_scheduler/docs/_replicator/bhl-lite-to-cloud" | python3 -m json.tool'
