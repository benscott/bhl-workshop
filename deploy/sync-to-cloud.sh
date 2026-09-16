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
# ----------------------------------------------------------------------------

echo "== 1/2  rsync bhl.db (~14 GB) -> Hetzner"
rsync -avP --inplace --partial \
  "$LOCAL_SQLITE" \
  "$HETZNER_SSH:$HETZNER_DIR/sites/bhl-name-timeline/bhl.db"

echo "== 2/2  set up CONTINUOUS CouchDB replication (Mini -> Hetzner)"
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
