# deploy — running the workshop sites on Hetzner

Ops code for serving the five `bhl-*` demo sites from a cloud box (Hetzner) as
the **primary** workshop server, with the Mac mini in Glasgow as dev / backup.

The workshop content (the top-level `README.md` of this repo) links to these
sites at `https://iphylo.org/<site>/`. Those links are what must stay up.

This directory does **not** contain the site code. Each site lives in its own
GitHub repo and is cloned in by `bootstrap.sh`:

| Site | Repo | Heavy data |
|------|------|------------|
| `bhl-all-the-pages` | `rdmpage/bhl-all-the-pages` | generated tiles/cache (rebuildable) |
| `bhl-image-search`  | `rdmpage/bhl-image-search` | none (calls the search API) |
| `bhl-light`         | `rdmpage/bhl-light` | CouchDB `bhl-lite` (~6 GB) + images (already on Hetzner) |
| `bhl-name-timeline` | `rdmpage/bhl-name-timeline` | `bhl.db` SQLite (~14 GB) |
| `bhl-mcp`           | `rdmpage/bhl-workshop-rdf-mcp` | none (wraps a remote SPARQL endpoint) |

## Layout

```
deploy/
├── docker-compose.yml   # Apache+PHP (serves all five sites) + CouchDB
├── .env.template        # copy to .env on the server, fill in secrets
├── bootstrap.sh         # run ON HETZNER: clone repos into ./sites, bring stack up
├── sync-to-cloud.sh     # run ON THE MINI: push bhl.db + CouchDB to Hetzner
├── RUNBOOK.md           # step-by-step provisioning + failover
└── sites/               # cloned site repos (gitignored)
```

## Why sync runs *from the Mini*

The Mini is behind home NAT, so Hetzner can't reach in to pull. All sync is an
**outbound push from the Mini** to Hetzner's public IP:

- CouchDB: a continuous replication document on the Mini pushing `bhl-lite` → Hetzner.
- SQLite `bhl.db`: `rsync` over SSH.

Images are already on Hetzner (imgproxy `images.bionames.org` + S3), so they
never touch this pipeline.

## Secrets

Nothing secret is committed. Sites read config via `getenv()`, fed from a `.env`
file that exists only on the server — no per-site `env.php` is deployed.
This repo is public; keep it that way by keeping `.env` out of it.

See `RUNBOOK.md` to get started.
