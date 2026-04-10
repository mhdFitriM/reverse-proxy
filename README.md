# Reverse Proxy

This folder is the public VPS entry point for all domains on the same IP.

## Purpose

- Terminate HTTPS on ports `80` and `443`
- Route FaceApp domains to the FaceApp stack on `127.0.0.1:8082`
- Route QBotu domains to the QBotu stack on `127.0.0.1:8081`
- Run on the Ubuntu VPS host network so `127.0.0.1` means the VPS itself

## Files

- `docker-compose.yml` runs the public Caddy instance
- `Caddyfile` routes domains to the correct local upstream
- `.env` stores your real domains and ACME e-mail

For FaceApp, the API domain is intentionally served on both HTTP and HTTPS because the legacy face gateway still expects a plain HTTP image and callback URL.

## Setup

1. Copy `.env.example` to `.env`
2. Put your real domains in `.env`
3. Start with `docker compose up -d`

Important:

- this stack is intended for the Linux VPS only
- it uses `network_mode: host`, so no other service on the VPS should bind public `80` or `443`
- do not leave `example.com` placeholders in `.env`, especially `QBOTU_MINIO_DOMAIN`

## Expected App Setup

### FaceApp

Use the existing stack in `faceapp_main` with the VPS override file:

- copy `.env.vps.example` to `.env`
- review the real domain values
- run `docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --build`

The VPS override binds FaceApp only on `127.0.0.1:8082` and swaps in the shared-proxy Caddyfile automatically.

### QBotu

Use `project_qbotu_a3/docker-compose.production.yml` with the VPS override file:

- copy `.env.vps.example` to `.env`
- review the real domain and secret values
- run `docker compose -f docker-compose.production.yml -f docker-compose.vps.yml up -d --build`

The VPS override binds only the QBotu web proxy on `127.0.0.1:8081`.
Postgres, Redis, and MinIO stay private on Docker networks by default.

QBotu already does its own internal hostname routing, so the public reverse proxy can send all QBotu domains to the same local upstream port.
