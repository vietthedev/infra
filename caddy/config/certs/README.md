# Client trust CA for Cloudflare AOP

Place `cloudflare-origin-pull-ca.pem` in this directory before running `caddy validate`.

For **Global Authenticated Origin Pulls**, download the official *Authenticated Origin Pull* CA certificate (not the Cloudflare Origin CA certificate):

```sh
curl -fLsS https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o config/certs/cloudflare-origin-pull-ca.pem
openssl x509 -in config/certs/cloudflare-origin-pull-ca.pem -noout -subject -issuer
```

For zone-level or per-hostname Authenticated Origin Pulls with custom certificates,
use the CA that signed your Cloudflare **client** certificate instead.
Do not put server private keys in this folder or Git.
