# Caddy reverse proxy for vietthe.dev

Ported from CentOS 7 Nginx to Debian 13, using Docker Compose and Cloudflare DNS-01.

## Preconditions

- New Debian VPS already has Docker Engine and Docker Compose v2 installed.
- `salad` has Docker access (or use `sudo docker`). Membership in the Docker group grants root-equivalent privileges.
- Cloudflare has `vietthe.dev` set to **Full (strict)**, with orange-cloud **proxied** DNS records for `asf`, `manabie`, `nana` pointing to the new VPS IPv4 (and IPv6 if configured).
- **Global** Authenticated Origin Pulls (AOP) is enabled on the NEW `vietthe.dev` zone. For zone/per-hostname custom AOP, see `config/certs/README.md` and substitute the appropriate CA.
- Cloudflare provides valid edge certificates covering these names (verify in dashboard).
- The ASF Docker service is prepared separately and joins the external Docker network `proxy`.
- Static websites copied into `/srv/www/manabie` and `/srv/www/nana`.
- Port 80/TCP, 443/TCP, optionally 443/UDP reachable via host firewall/provider firewall.

## Create a scoped Cloudflare token

Create an API token scoped to the **vietthe.dev** zone:

- Zone → Zone → Read
- Zone → DNS → Edit

Token is used ONLY by Caddy's DNS-01 ACME challenges.

```sh
cd ~/infra/caddy
mkdir -p secrets
chmod 700 secrets
# Insert the token using an editor, ensuring no trailing newline.
# e.g. `printf %s 'TOKEN_VALUE' > secrets/cloudflare_api_token` (avoid storing secret in shell history)
chmod 600 secrets/cloudflare_api_token
```

Secret is mounted at `/run/secrets/cloudflare_api_token` by Docker Compose, and intentionally excluded from Git.

## Download the appropriate AOP CA (public certificate)

```sh
curl -fLsS https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o config/certs/cloudflare-origin-pull-ca.pem
openssl x509 -in config/certs/cloudflare-origin-pull-ca.pem -noout -subject -issuer
```

This URL is for GLOBAL AOP only. This is not the Cloudflare Origin CA certificate. 

## Configure local files and shared network

```sh
sudo mkdir -p /srv/www/manabie /srv/www/nana
sudo chmod 755 /srv /srv/www /srv/www/manabie /srv/www/nana
# Transfer the old static site contents securely to those locations.
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
```

In the ASF Compose file, connect ASF to the same external bridge:

```yaml
services:
  asf:
    networks: [proxy]
networks:
  proxy:
    external: true
```

The host loopback bind `127.0.0.1:1242:1242` can remain, while Caddy reaches `asf:1242` via the Docker network. Ensure ASF binds on its container network interface, not only inside-container loopback.

## Build, validate and start

```sh
docker compose build
# Validates the configuration using the same custom image and mounted files.
docker compose run --rm --no-deps --entrypoint caddy caddy \
  validate --config /etc/caddy/Caddyfile --adapter caddyfile
# If all checks pass:
docker compose up -d
# Check issuance / errors:
docker compose logs -f --tail=100 caddy
```

Caddy can obtain public certs using DNS-01 before DNS A/AAAA records point to the new VPS. Use the Cloudflare dashboard to confirm new hostnames use proxied DNS and Full (strict). If ASF is not yet started, its proxy may return 502 until it's running.

After editing imported site snippets, run:

```sh
docker compose run --rm --no-deps --entrypoint caddy caddy \
  validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

**Test first**: after DNS points to Debian through Cloudflare, check each site from a client and ensure HTTP → HTTPS redirects, static SPA routes, and ASF login. Direct origin HTTPS calls without Cloudflare's client certificate should fail the TLS handshake. AOP does NOT authenticate end users; secure ASF with its own login and preferably Cloudflare Access.

## Backups and rollback

Back up the `caddy_data` Docker volume, not just the Git repository, to preserve managed private keys and ACME registration state. `caddy_config` also stores runtime configuration. Keep the old CentOS server available until the new services have been verified. Don't run `docker compose down -v` unless intentionally deleting persistent data.

## Security notes

- Avoid mounting `/var/run/docker.sock` inside Caddy.
- Treat Docker group membership as root-equivalent.
- Global AOP identifies traffic from the Cloudflare network, but not a specific Cloudflare account. If stronger origin protection is required, use zone/per-hostname AOP with your own client cert and/or allowlist Cloudflare source IPs on 443.
- Restrict Cloudflare token to one DNS zone; rotate it if compromised.
- Do not expose `asf:1242` directly to the internet.
- Avoid automated image upgrades until you can test them; Caddy/Cloudflare image versions are pinned in Dockerfile.
