# CI/CD setup — auto-deploy on push (one-time per repo)

This walks through the one-time setup so that every push to the trigger
branch (`main` for `reverse-proxy` and `face_auth`, `staging` for
`qparking`) auto-deploys to the VPS. After this is done, you never need
to SSH in to pull and run `docker compose` again.

Logs for every deploy live in **GitHub → repo → Actions tab**.

---

## How it works (the pattern)

1. You `git push`.
2. GitHub Actions spawns an Ubuntu runner.
3. The runner SSHs into your VPS using a deploy key you authorise once.
4. On the VPS, the script does:
   - `git fetch --all && git reset --hard origin/<branch>` — bring the
     working tree to exactly what was just pushed.
   - `docker compose -f ... -f docker-compose.vps.yml build --no-cache`
   - `docker compose -f ... -f docker-compose.vps.yml up -d --force-recreate`
   - For `reverse-proxy`, runs its own `deploy-vps.sh` which validates the
     Caddyfile before reloading.
5. Every command's stdout/stderr is streamed back into the GitHub Actions
   run log. A red ✗ in the Actions UI means deploy failed; expand the step
   to see the exact line and error.

No webhook listener on the VPS, no self-hosted runner to maintain, no
secrets stored on the VPS itself — the runner is ephemeral and discards
the SSH key once the job ends.

---

## One-time setup

### 1. Generate a deploy keypair on your local machine

```powershell
ssh-keygen -t ed25519 -C "github-actions-deploy" -f $HOME\.ssh\qbot-vps-deploy -N '""'
```

That writes two files:

- `~/.ssh/qbot-vps-deploy`      ← private key (you'll paste this into GH secrets)
- `~/.ssh/qbot-vps-deploy.pub`  ← public key (you'll add this to the VPS)

### 2. Authorise the public key on the VPS

```bash
# on the VPS, as the user that owns /opt/<projects>
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<paste contents of qbot-vps-deploy.pub>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

The same keypair authorises all three deployments — they share a VPS
user. If you want per-repo isolation, generate three pairs and use a
different one per repo.

### 3. Set GitHub secrets in each repo

Each of the three repos (`qparking`, `reverse-proxy`, `face_auth`) needs
the same four secrets. Go to **Settings → Secrets and variables → Actions
→ New repository secret**:

| Name           | Value                                                            |
| -------------- | ---------------------------------------------------------------- |
| `VPS_HOST`     | the VPS's IP or DNS name, e.g. `qbot.now` or `203.0.113.4`        |
| `VPS_USER`     | the SSH username on the VPS (`root` or `deploy` or whatever)     |
| `VPS_SSH_KEY`  | full contents of `qbot-vps-deploy` (the private key, PEM block)  |
| `VPS_PORT`     | optional, only if SSH isn't on 22                                |

### 4. Make sure each project is already cloned on the VPS

The workflows assume:

```
/opt/qparking         (origin = github.com/seancreative/qparking, branch staging)
/opt/reverse-proxy    (origin = github.com/mhdFitriM/reverse-proxy, branch main)
/opt/face_auth        (origin = github.com/mhdFitriM/face_auth, branch main)
```

If any are missing, clone them once:

```bash
cd /opt
sudo git clone https://github.com/seancreative/qparking.git
sudo git clone https://github.com/mhdFitriM/reverse-proxy.git
sudo git clone https://github.com/mhdFitriM/face_auth.git
```

The user owning these checkouts must be the same user `VPS_USER`
authenticates as in step 3.

### 5. Each project needs its `.env` on the VPS

The workflows do **not** generate or modify `.env` files — those live on
the VPS only and survive across pulls. If you've already followed the
standard deploy once (`cp .env.vps.example .env && nano .env`), this is
already done.

---

## Verifying the deploy pipeline

After setup, push a trivial change to the trigger branch and watch:

1. **GitHub → repo → Actions** — you'll see a new run named "Deploy …".
2. Click into it. The `Deploy via SSH` step expands to show the live log
   (git pull → docker build → docker up → docker compose ps output).
3. Green check ✓ = deployed. Red ✗ = expand to read the line that
   failed; the error is usually `permission denied` (key not authorised),
   `no such file or directory` (project not cloned), or a build error
   you'd see on a normal `docker compose build`.

You can also trigger a deploy manually from the Actions tab via the
**Run workflow** button (we set `workflow_dispatch` on every workflow).

---

## Why this method (vs. the alternatives)

| Option | Why we didn't pick it |
| --- | --- |
| **GitHub webhook → tiny listener on VPS** | One more long-running process to babysit; HMAC validation to write; logs scattered across journald + GH UI. |
| **Self-hosted GitHub Actions runner on the VPS** | Runner needs constant patching and a SystemD unit; harder to revoke if compromised; CPU/RAM contention with your apps. |
| **Cron polling `git pull` on the VPS** | Lag (no instant feedback); no log surface in GH UI; hard to debug failed pulls. |
| **GitHub Actions + SSH (this setup)** | One ephemeral key, no daemons on the box, native log streaming in the Actions UI, manual trigger built-in, easy to revoke (just remove the public key from `authorized_keys`). |

The SSH pattern is what most one-VPS solo operators converge on for the
same reasons. No frameworks, no extra services, fully transparent.

---

## Rolling back a bad deploy

The workflows `git reset --hard` to the latest pushed commit, so a bad
deploy is fixed by pushing a revert:

```bash
git revert <bad-sha>
git push
```

That triggers a fresh deploy with the reverted code. Same flow, no SSH.

If you're stuck and need an emergency rollback, SSH in and:

```bash
cd /opt/<project>
git log --oneline -10        # find the good sha
git reset --hard <good-sha>
docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --force-recreate
```
