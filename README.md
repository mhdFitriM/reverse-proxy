# Reverse Proxy

This folder is the public VPS entry point for all domains on the same IP.

## Purpose

- Terminate HTTPS on ports `80` and `443`
- Route FaceApp domains to the FaceApp stack on `127.0.0.1:8082`
- Route QBotu domains to the QBotu stack on `127.0.0.1:8081`

## Files

- `docker-compose.yml` runs the public Caddy instance
- `Caddyfile` routes domains to the correct local upstream
- `.env` stores your real domains and ACME e-mail

## Setup

1. Copy `.env.example` to `.env`
2. Put your real domains in `.env`
3. Start with `docker compose up -d`

## Expected App Setup

### FaceApp

Use the existing stack in `faceapp_main`, but on the VPS set:

- `FACEAPP_PROXY_HTTP_BIND=127.0.0.1:8082`
- `FACEAPP_PROXY_HTTPS_BIND=127.0.0.1:8442`
- `FACEAPP_CADDYFILE=./infra/caddy/Caddyfile.shared-proxy`

### QBotu

Use `project_qbotu_a3/docker-compose.production.yml`, and on the VPS set:

- `HTTP_HOST_PORT=127.0.0.1:8081`
- `FRONTEND_URL=https://your-qbotu-domain`
- `API_URL=https://your-qbotu-api-domain`
- `VITE_API_BASE_URL=https://your-qbotu-api-domain/api`
- `REVERB_PUBLIC_PORT=443`
- `REVERB_PUBLIC_SCHEME=https`

QBotu already does its own internal hostname routing, so the public reverse proxy can send all QBotu domains to the same local upstream port.
