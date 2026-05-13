# Adding a new project behind this reverse proxy

The VPS hosts many small docker-compose stacks under `/opt`, all sharing this
Caddy reverse proxy for TLS + public routing. Each stack binds only to
`127.0.0.1:<unique-port>` so it stays private; the shared Caddy fans out the
public domain to the right port.

This is the checklist to add a new app, e.g. a hypothetical `myapp`.

---

## 1. Pick a free localhost port

Used so far:

| Port | Project |
|---|---|
| `8081` | QBotu (web proxy) |
| `8082` | FaceApp (internal Caddy that splits admin/API) |
| `8083` | QRPos |
| `8084` | face_auth (backend) |
| `8085` | face_auth (admin UI) |
| `8086` | QParking (Laravel backend) |
| `8087` | QParking (Vite frontend) |
| `8088` | **next free — use this** |

Pick the next number. Avoid:

- `80`, `443` (owned by this Caddy)
- `9001` (MinIO console — face_auth)
- Anything `lsof -i :PORT` shows in use on the VPS

If your app exposes multiple services that need separate public domains,
allocate **one port per service** rather than relying on internal Host-header
routing (face_auth does this — `8084` for backend, `8085` for admin).

---

## 2. Inside your app: bind to `127.0.0.1` only

Create `myapp/docker-compose.vps.yml`:

```yaml
services:
  web:
    ports: !override
      - "127.0.0.1:${MYAPP_PORT:-8086}:80"
```

The `!override` is **important** — it replaces the dev `ports:` array entirely
so the service is NOT bound on `0.0.0.0` in prod. Without `!override`, compose
*merges* port lists and you'd accidentally expose the dev port publicly.

Create `myapp/.env.vps.example` so future-you remembers what to set:

```
COMPOSE_PROJECT_NAME=myapp
MYAPP_DOMAIN=myapp.qbot.now
MYAPP_PORT=8086
## ... real secrets ...
```

---

## 3. Add the domain + upstream to this folder's `.env.example`

```
MYAPP_DOMAIN=myapp.example.com
MYAPP_UPSTREAM=127.0.0.1:8086
```

Document them with `example.com` placeholders — the real values go in `.env`
on the VPS, never committed.

---

## 4. Add a block to `Caddyfile`

Simplest case — one domain → one upstream:

```caddy
{$MYAPP_DOMAIN} {
    import common_headers
    header Strict-Transport-Security "max-age=31536000"
    reverse_proxy {$MYAPP_UPSTREAM}
}
```

If your app's frontend & backend run on different localhost ports but should
share a single public domain (face_auth pattern):

```caddy
{$MYAPP_DOMAIN} {
    import common_headers
    header Strict-Transport-Security "max-age=31536000"

    @backend path /api/* /ws/* /healthz
    handle @backend {
        reverse_proxy {$MYAPP_API_UPSTREAM}
    }

    handle {
        reverse_proxy {$MYAPP_ADMIN_UPSTREAM}
    }
}
```

If the upstream needs to know the public scheme/host (rare with TLS-terminating
Caddy, but Laravel-style frameworks often want it):

```caddy
reverse_proxy {$MYAPP_UPSTREAM} {
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-For {remote}
}
```

Common gotchas:

- **WebSockets**: Caddy `reverse_proxy` upgrades automatically, no extra config.
- **Large uploads** (image enrol, CSV bulk import): add a `request_body { max_size 25MB }` block.
- **Plain HTTP fallback** (legacy devices that can't do TLS): wrap in
  `http://{$MYAPP_DOMAIN}` block alongside the HTTPS one and only allow the
  specific paths that need it. FaceApp does this for the `/api/device/callbacks/*`
  path.
- **Multiple subdomains** sharing one upstream (e.g. `admin.foo.com` and
  `api.foo.com` both → `:8082` because the app has its own internal Caddy):
  just write two separate blocks pointing at the same `{$MYAPP_UPSTREAM}`.

---

## 5. Set the real domain in DNS

In your registrar / Cloudflare, point an A record (and AAAA if you have IPv6)
for `myapp.qbot.now` → VPS public IP. Caddy will mint a Let's Encrypt cert
automatically the first time someone hits the domain.

**For face_auth specifically**: turn OFF the Cloudflare proxy (grey cloud
DNS-only) on the subdomain that handles the agent WebSocket. Cloudflare's
proxy can interfere with long-lived WebSocket connections on the free tier.

---

## 6. Deploy

On the VPS:

```bash
# Bring up your app first
cd /opt/myapp
cp .env.vps.example .env
nano .env   # real values
docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --build

# Then update the shared reverse proxy
cd /opt/reverse-proxy
nano .env   # add MYAPP_DOMAIN + MYAPP_UPSTREAM
./deploy-vps.sh   # validates Caddyfile and reloads in place
```

`deploy-vps.sh` does:
1. `git pull --ff-only` if it's a git repo
2. `docker compose up -d`
3. `caddy validate` — fails fast if the Caddyfile has a syntax error
4. `caddy reload` — zero-downtime reload; falls back to restart if reload fails

---

## 7. Verify

```bash
# DNS resolves
dig +short myapp.qbot.now

# Cert issued + service responds
curl -I https://myapp.qbot.now

# App listening on the right localhost port (not public!)
sudo ss -lntp | grep ":8086 "
# Should show 127.0.0.1:8086 — NOT 0.0.0.0:8086
```

If you see `0.0.0.0:8086` your `docker-compose.vps.yml` override didn't take —
re-check the `!override` keyword and that you passed BOTH compose files.

---

## Quick reference: ports

Keep this table updated as you add projects:

```
8081  QBotu                /opt/project_qbotu_a3
8082  FaceApp               /opt/faceapp_main
8083  QRPos                 /opt/qrpos
8084  face_auth (backend)   /opt/face_auth
8085  face_auth (admin)     /opt/face_auth
8086  qparking (backend)    /opt/qparking
8087  qparking (frontend)   /opt/qparking
8088  (next free)
```

## What's at risk if you skip a step

| If you skip... | What goes wrong |
|---|---|
| `127.0.0.1:` prefix | Your app's port is publicly exposed, bypassing Caddy + TLS |
| `!override` keyword | Same — compose merges port lists, leaks dev port to public |
| Adding the domain to `.env` | Caddy block references an empty `{$MYAPP_DOMAIN}` and refuses to start |
| `deploy-vps.sh` after Caddyfile change | New config sits unloaded, app is unreachable until reload |
| DNS A record | Let's Encrypt fails the HTTP-01 challenge, no cert, only port-80 redirect works |
