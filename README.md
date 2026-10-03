# Installing ProductOwner

ProductOwner runs on **one Linux server with Docker**: the app, its PostgreSQL database, the video server for
meetings and automatic HTTPS. Each company runs its own copy, on a cloud server or in its own data center.

## What you need

| | |
| --- | --- |
| Server | Linux (Ubuntu 22.04/24.04 or Debian 12), 2 CPUs and 4 GB memory for up to ~50 people; 4 CPUs / 8 GB with regular meetings. Intel/AMD or ARM. |
| Disk | 40 GB to start. Meeting recordings use about 0.5 GB per hour. |
| Docker | Docker Engine with the Compose plugin: `curl -fsSL https://get.docker.com \| sh` |
| Names | One DNS name for the app (e.g. `productowner.acme.com`), and one for meetings (e.g. `meet.productowner.acme.com`), both pointing at the server. |
| Firewall | In: TCP 80 and 443. For meetings also TCP 7881 and UDP 7882. |
| Email (optional) | An SMTP account for invitations, password resets and meeting recaps. |

## Install

1. Download the install files to the server, e.g. into `/opt/productowner`:

   ```bash
   sudo mkdir -p /opt/productowner && sudo chown "$USER" /opt/productowner && cd /opt/productowner
   curl -fsSL https://github.com/lotfy2125/productowner-install/releases/latest/download/productowner-install.tar.gz | tar xz --strip-components=1
   ```

2. Run the installer and answer its questions:

   ```bash
   cd /opt/productowner
   ./install.sh
   ```

   Without questions: `./install.sh --domain productowner.acme.com --email it@acme.com --yes`
   (add `--no-meetings` to leave meetings off).

3. Open `https://productowner.acme.com`. The first person to open it creates the **admin account** and the first
   project, then invites the team from **Settings → Team**.
4. Add your licence: **Settings → Licence → Open licence file**. Until then ProductOwner runs as a trial.

The installer writes `.env` with fresh secrets. **Keep a copy of `.env` somewhere safe**, apart from the backups:
`PO_SECRET` in it unlocks the access tokens saved in the database.

### Servers without internet

Bring the image as a file (`productowner-image-<version>-amd64.tar.gz` from the release) and run
`./install.sh --image-file productowner-image-<version>-amd64.tar.gz`. HTTPS certificates from Let's Encrypt need the
server to be reachable from the internet; on an internal network put your company's certificate in Caddy instead
(see “Your own certificate” below).

## Settings

Change `.env`, then `docker compose up -d` to apply.

| Setting | What it does |
| --- | --- |
| `DOMAIN`, `ACME_EMAIL` | The address and the email for certificate notices. |
| `SMTP_URL`, `EMAIL_FROM` | Sending email, e.g. `smtps://user:password@smtp.office365.com:465`. Without it, emails are written to the app log (`docker compose logs app`). |
| `ANTHROPIC_API_KEY` | The PO agent uses Claude to draft stories and meeting recaps; without a key it uses built-in rules. |
| `COMPOSE_PROFILES=meetings` | Meetings on. Empty: off. |
| `MEET_DOMAIN`, `LIVEKIT_PUBLIC_URL` | The meetings address (`wss://` + `MEET_DOMAIN`). |
| `PRODUCTOWNER_VERSION` | Which version runs (`latest` or e.g. `1.2.0`). |

Meetings on a private network (office server, VPN): set `node_ip` in `livekit.yaml` to the server's address on that
network.

### Your own certificate

Put the certificate and key next to the Caddyfile and replace the `{$DOMAIN}` block's first line with:

```
{$DOMAIN} {
	tls /etc/caddy/cert.pem /etc/caddy/key.pem
```

and mount them in `docker-compose.yml` under `caddy.volumes`.

## Every day

| | |
| --- | --- |
| Back up | `./backup.sh` — database and files into `backups/<date>`, keeps the newest 14. Put it in cron: `30 2 * * * /opt/productowner/backup.sh`, and copy `backups/` off the server. |
| Restore | `./restore.sh backups/20261002-023000` |
| Update | `./update.sh` (newest) or `./update.sh 1.2.0`. It backs up first; the database is brought up to date when the app starts. |
| Logs | `docker compose logs -f app` |
| Status | `docker compose ps` — all services should say `running (healthy)`. |
| Stop / start | `docker compose stop` / `docker compose up -d` |

## What runs

| Service | |
| --- | --- |
| `caddy` | HTTPS in front of everything; gets and renews certificates. |
| `app` | ProductOwner (API and web app), port 3000 inside. Files (recordings, transcripts, recaps) in the `app-files` volume. |
| `postgres` | The database, in the `postgres-data` volume. Not reachable from outside. |
| `livekit` | The video server for meetings. |

## Licence

A new install runs as a **trial**: 14 days, up to 25 people (clients don't count). An admin adds the licence file in
**Settings → Licence**; it says how many people, until when, and what's included. 30 days before the end, admins see a
reminder. After the end date everything keeps working for 14 more days, then ProductOwner becomes **read-only**:
everyone can still sign in and read everything, nothing can be changed until the renewed licence is added. Nothing is
ever deleted.
