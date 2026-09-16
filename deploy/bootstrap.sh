#!/usr/bin/env bash
# Run ON THE HETZNER BOX. Clones the site repos, installs deps, brings the
# stack up. Idempotent-ish: re-running pulls latest and re-ups.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "!! No .env — copy .env.template to .env and fill it in first." >&2
  exit 1
fi
set -a; . ./.env; set +a

# Preflight ------------------------------------------------------------------
for c in git docker; do
  command -v "$c" >/dev/null 2>&1 || { echo "!! $c not installed" >&2; exit 1; }
done

# bhl-light tracks tagging/uber_h3.db via git-lfs. Without git-lfs the clone
# still succeeds but leaves a pointer file. That's harmless for the workshop
# (only the tagging/data-prep scripts read it), so warn rather than fail.
if ! command -v git-lfs >/dev/null 2>&1; then
  echo "-- note: git-lfs not installed; bhl-light/tagging/uber_h3.db will be a"
  echo "   pointer, not the real file. The UI doesn't need it. To get it:"
  echo "   apt-get install -y git-lfs && git lfs install"
fi

mkdir -p sites couch-data
cd sites

clone_or_pull () { # $1 = repo url, $2 = dir
  if [[ -d "$2/.git" ]]; then
    echo "== updating $2"; git -C "$2" pull --ff-only
  else
    echo "== cloning $2"; git clone "$1" "$2"
  fi
}

clone_or_pull https://github.com/rdmpage/bhl-light.git          bhl-light
clone_or_pull https://github.com/rdmpage/bhl-name-timeline.git  bhl-name-timeline
clone_or_pull https://github.com/rdmpage/bhl-all-the-pages.git  bhl-all-the-pages
clone_or_pull https://github.com/rdmpage/bhl-image-search.git   bhl-image-search

# bhl-light uses Composer (vendor/ is gitignored).
if [[ -f bhl-light/composer.json ]]; then
  ( cd bhl-light && docker run --rm -v "$PWD":/app composer:2 install --no-dev )
fi

cd ..
docker compose up -d

# CouchDB 3.x does not create its own system databases, and an empty _all_dbs
# means a single node logs warnings and some endpoints fail. Wait for it to
# answer, then create them. Idempotent: a re-run just gets 412 file_exists.
echo "== waiting for CouchDB"
for _ in $(seq 1 30); do
  curl -sf -m 2 http://127.0.0.1:5984/ >/dev/null 2>&1 && break
  sleep 2
done
for db in _users _replicator _global_changes; do
  curl -s -o /dev/null -X PUT \
    -u "$COUCHDB_USERNAME:$COUCHDB_PASSWORD" \
    "http://127.0.0.1:5984/$db"
done
echo "== CouchDB system databases ensured"

echo
echo "Stack up. Now sync data from the Mini with sync-to-cloud.sh (run on the Mini)."
echo "Remaining manual porting — see RUNBOOK.md 'Portability fixes'."
