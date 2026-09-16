# RUNBOOK — BHL workshop on Hetzner

Goal: Hetzner is the **primary** workshop server; the Mac mini is dev/backup.
Data flows **Mini → Hetzner** (outbound push, works through home NAT).

## 0. Provision the box
**CX33 (4 vCPU / 8 GB RAM / 80 GB disk), Helsinki (hel1)** — closest region to Oslo.

Measured payload (2026-09-16):

| Item | Size |
|------|------|
| `bhl.db` (SQLite) | 13 GB |
| CouchDB `bhl-lite` (52,768 docs) | 6.1 GB |
| `bhl-all-the-pages` `tiles/` + `cache/` | 4.3 GB |
| site code | ~3 MB |
| **total data** | **~23.4 GB** |

Plus OS + Docker (~4 GB), images (~1 GB), and ~6 GB transient headroom for
CouchDB compaction (it rewrites the whole `.couch` file). That's a ~35 GB floor,
so the 40 GB tier (CX23/CAX11) is too tight — take the 80 GB tier rather than
adding a volume. The 8 GB RAM matters mostly as OS page cache for the 13 GB
SQLite; CouchDB itself is fine in ~2 GB at this doc count.

CAX21 (Arm, same 4/8/80) also works — both `php:8.3-apache` and `couchdb:3.4`
ship arm64 images — but x86 is the safer bet for a box you can't debug live.
- Install Docker + docker compose, `git`, and (optionally) `git-lfs`.
  Open ports 80/443; restrict 5984 to the Mini's IP (or only expose CouchDB
  via the TLS proxy).
- Clone this repo and work in `deploy/`:
  ```
  git clone https://github.com/rdmpage/bhl-workshop.git /opt/bhl-workshop
  cd /opt/bhl-workshop/deploy
  ```

## 1. Configure
```
cp .env.template .env && $EDITOR .env      # fill in secrets
```

## 2. Bring the stack up (on Hetzner)
```
./bootstrap.sh
```
Sites now serve on `:8080/bhl-light/`, `:8080/bhl-image-search/`, etc.

## 3. Sync data (on the Mini)
```
./sync-to-cloud.sh        # edit the HETZNER_* / COUCH vars first
```
- rsyncs `bhl.db` up (13 GB, resumable via `--partial --inplace`).
- tar-streams `bhl-all-the-pages`' generated tiles/cache (4.3 GB / 545k files).
- installs a **continuous** CouchDB replication doc so `bhl-lite` stays current.

Total upload is **~23 GB**. On a typical domestic upstream that is several
hours — start days before the workshop, not the night before.

## 4. Serve on the workshop URLs
The workshop content links to `https://iphylo.org/<site>/`, and the container
already serves that exact `/<site>/` path layout — so front it with
Caddy/Traefik for TLS and point the hostname at Hetzner. Keeping the same
hostname means **no links in the workshop README need to change**.

If you'd rather not move `iphylo.org` itself, use a second hostname
(e.g. `bhl-workshop.iphylo.org`) and update the 7 links in the top-level
`README.md` — but then the Mini is back in the critical path unless you switch.

Lower the DNS TTL a day or two beforehand so a failover switch takes effect fast.

---

## Porting notes

1. **bhl-light `config.inc.php`** has Mac-specific hardcoded paths — the
   `/Users/rpage/...` SQLite path and the Mountain Duck S3 mount.
   **Not blocking:** these are only used by the data-*import* scripts; no part of
   the user interface depends on them, so the site serves fine on Hetzner
   without touching them. Leave as-is for the workshop.

2. **bhl-all-the-pages**: `cells.php`, `tiles/` and `cache/` are generated &
   gitignored, so a bare `git clone` won't render. `sync-to-cloud.sh` now pushes
   them (step 2/3) as a tar stream — it's ~545,000 tiny files, and rsync at that
   file count is dominated by per-file round-trips. Rebuilding on the server
   (`build_cells.php`, `build_tiles.php`) is the fallback but means re-fetching
   from BHL. The tar stream isn't resumable; if it dies, re-run it.

3. **bhl-light + git-lfs**: `tagging/uber_h3.db` is an LFS object. Install
   git-lfs on the box (`apt-get install -y git-lfs && git lfs install`) and it
   clones as the real 196K SQLite file. Without git-lfs the clone still
   succeeds but leaves a pointer — harmless, since only the tagging/data-prep
   scripts read it. `bootstrap.sh` warns if that's the case.
   (Verified 2026-09-16: with git-lfs installed, all four repos clone clean.)

4. **bhl-image-search** needs `BHL_SEARCH_API` + `BHL_SEARCH_KEY` in `.env`
   (copy the real values from the Mini's gitignored `env.php`). It calls a
   separate CLIP search API — confirm that box is up, it is *not* part of this
   compose stack.

5. **Secrets** (CouchDB pw, BHL API key, imgproxy key/salt, search key) live only
   in the server's `.env`. This repo is public — if any were ever committed
   anywhere, rotate them.

## Keeping the backup fresh
- CouchDB: continuous replication handles it automatically.
- `bhl.db`: re-run `sync-to-cloud.sh` (or cron it on the Mini) when it changes.
