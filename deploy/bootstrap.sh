#!/usr/bin/env bash
# Run ON THE HETZNER BOX. Clones the site repos, installs deps, brings the
# stack up. Idempotent-ish: re-running pulls latest and re-ups.
set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# The demo sites. TO ADD ONE: append a "<repo-url> <dir>" line here, re-run this
# script, done. The dir name is also the URL path -- sites/foo is served at
# /foo/ -- because docker-compose bind-mounts this whole directory into the web
# container, so a new site needs no compose edit and no restart.
#
# Caveats for a new demo:
#   - the repo must be PUBLIC (cloned over unauthenticated https)
#   - a composer.json is handled automatically (see below)
#   - PHP here is lean: pdo_sqlite, curl, mbstring, dom, xml. Anything needing
#     gd / intl / zip / pdo_mysql / pdo_pgsql must be added to the
#     docker-php-ext-install line in docker-compose.yml
#   - generated or bulk data (cf. bhl-all-the-pages tiles/) needs its own step
#     in sync-to-cloud.sh; a git clone alone will not carry it
# ---------------------------------------------------------------------------
SITES=(
  "https://github.com/rdmpage/bhl-light.git          bhl-light"
  "https://github.com/rdmpage/bhl-name-timeline.git  bhl-name-timeline"
  "https://github.com/rdmpage/bhl-all-the-pages.git  bhl-all-the-pages"
  "https://github.com/rdmpage/bhl-image-search.git   bhl-image-search"
)

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

for entry in "${SITES[@]}"; do
  read -r url dir <<<"$entry"
  clone_or_pull "$url" "$dir"
done

# Any site with a composer.json gets its deps installed -- vendor/ is gitignored
# so it never arrives with the clone, and a missing one is an autoload fatal.
for dir in */; do
  dir=${dir%/}
  if [[ -f "$dir/composer.json" ]]; then
    echo "== composer install for $dir"
    ( cd "$dir" && docker run --rm -v "$PWD":/app composer:2 install --no-dev )
  fi
done

# SQLite in WAL mode creates -wal/-shm sidecars beside the database even for
# read-only queries, so the directory must be writable by the web container's
# www-data (uid 33) or every SELECT fails with "attempt to write a readonly
# database". Applies to any site shipping a .db, so new demos get it too.
for dir in */; do
  dir=${dir%/}
  if compgen -G "$dir/*.db" >/dev/null 2>&1; then
    echo "== $dir ships a SQLite db; making it writable by www-data"
    chown -R 33:33 "$dir"
  fi
done

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
