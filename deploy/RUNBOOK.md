# RUNBOOK — BHL workshop on Hetzner

Goal: Hetzner is the **primary** workshop server; the Mac mini is dev/backup.
Data flows **Mini → Hetzner** (outbound push, works through home NAT).

## 0. Provision the box
- Hetzner CX22/CPX11 + a ~40 GB volume (code + `bhl.db` ~14 GB + CouchDB ~6 GB).
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
- rsyncs `bhl.db` up (~14 GB — do this well before the workshop).
- installs a **continuous** CouchDB replication doc so `bhl-lite` stays current.

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

2. **bhl-all-the-pages**: `cells.php` / `tiles/` are generated & gitignored.
   Either rsync them up or rebuild on the server (`build_cells.php`,
   `build_tiles.php`). Do this before the workshop — it's the one site that
   won't work straight out of a `git clone`.

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
