#!/usr/bin/env bash
# Run ON THE HETZNER BOX. Clones the site repos, installs deps, brings the
# stack up. Idempotent-ish: re-running pulls latest and re-ups.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "!! No .env — copy .env.template to .env and fill it in first." >&2
  exit 1
fi

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
echo
echo "Stack up. Now sync data from the Mini with sync-to-cloud.sh (run on the Mini)."
echo "Remaining manual porting — see RUNBOOK.md 'Portability fixes'."
