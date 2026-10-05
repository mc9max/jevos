# Deploy and Host

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/jevos)

**JevOS** is an open-source, CPU-only alternative to [TypeSafe Jev](https://typesafe.com/jev) for yes/no decisions — ship it and your application can ask a small model, entirely offline, "is this X?" and get back `P(yes)` in tens of milliseconds. It runs [jevos-v3](https://github.com/feder-cr/jev) (MiniCPM5-1B cut to 17 layers with a single-logit head, INT8 OpenVINO weights) on the CPU in a single binary — no Python, no GPU, no database, no companion service.

- API: **`POST /v1/systemone`** with `{model?, state, questions}` — TypeSafe's wire format, so existing Jev clients work unchanged
- **`GET /health`** — liveness + model fingerprint, unauthenticated (Railway's healthcheck target)
- Optional lock-down: set **`JEV_API_KEY`** and every endpoint except `/health` requires the `Authorization: Bearer *** header

## Why Deploy

A lot of product logic is "given this state, is this condition true?" — should we refund, is this message fraudulent, has the agent followed its rules, will this patch apply without conflict. TypeSafe's hosted Jev answers these, but it's a per-token cloud API you don't own. JevOS is the self-hosted path: the same yes/no contract, the same wire format, running on your silicon.

- **Offline by design** — after the container starts there is no network dependency. The model is baked into the image; requests never leave your network.
- **CPU-only, one binary** — Intel OpenVINO INT8 inference. 25–110 ms per short request on a laptop; no CUDA, no GPU, no driver matrix.
- **Jev-compatible surface** — it speaks TypeSafe's wire format on `/v1/systemone`, so a Jev SDK or `curl` keeps working (point the base URL at this service and yes/no calls come back as `noul` = P(yes)).
- **Lightweight and stateless** — no volume, no migration, no storage to lose; a redeploy is a clean re-run.

## About Hosting

Single service, Dockerfile build. The heavy lifting (the ~630 MB int8 model) is downloaded and SHA-256-verified at build time into a `debian:trixie-slim` runtime:

1. **Pinned release** — the binary *and* the model come from the same tagged `jevos-v3` release, so the serving code and the weights are from one build. Integrity is checked against the release's `SHA256SUMS.txt` before the model is copied in.
2. **Non-root runtime** — the container runs as uid 1000. Nothing is volume-mounted, so there is nothing root-owned for the Railway volume trap to collide with.
3. **Port injected correctly** — the entrypoint reads `PORT` (Railway's value) and binds `0.0.0.0:$PORT`, so the public domain routes to the app.
4. **In-image healthcheck** — `curl` probes `/health` on `$PORT` with a short boot window, matching the `railway.json` healthcheck.
5. **Optional lock-down** — set `JEV_API_KEY` to require a Bearer token; leave it blank for an open instance (the default).

No volume is created: the service is fully stateless.

## Dependencies for JevOS

### Deployment Dependencies

JevOS needs nothing external at runtime — the model is self-contained and free. The deploy form offers one optional field:

| Variable | In deploy form | Required | Purpose |
|---|---|---|---|
| `JEV_API_KEY` | Yes | No (blank = open) | When set, `Authorization: Bearer *** is required on every endpoint except `/health`. Locks a shared instance down; clear it to open it back up. |

Two advanced runtime knobs are **not** in the form (they keep the release's tested defaults; set them in the service's **Variables** panel if you need to):

| Variable | Default | Purpose |
|---|---|---|
| `JEV_THREADS` | auto (all logical CPUs) | OpenVINO thread count — lower it to leave CPU headroom on a shared instance. |
| `JEV_CTX` | `8192` | Context window in tokens (the model's supported max). |

There are no API keys to obtain: this *is* the model. If you want to lock a shared instance down, generate any secret for `JEV_API_KEY` and redeploy.

## Ports

- **`8080`** — the Jev API + `/health`. The service binds the `PORT` variable Railway provides, so the public domain routes to it automatically; no port change is needed.

## Common Use Cases

- A private, self-hosted yes/no decision endpoint in front of your app — post `{state, questions}` and read back P(yes), with no per-token cloud billing
- A Jev-compatible drop-in: point an existing Jev client at this service's URL for yes/no calls while staying on your own hardware
- An offline/air-gapped decision service where data cannot leave the network
- A small, auditable model-serving reference: one container, one binary, pinned by release hash
