# netproof — Vérifier la joignabilité d’un site (DNS → IP → TCP:443 → HTTP)

[![CI](https://github.com/VARELAdavidhugo/netproof/actions/workflows/ci.yml/badge.svg)](https://github.com/VARELAdavidhugo/netproof/actions/workflows/ci.yml)  
![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)  

## 🧭 Sommaire
- [Pourquoi ?](#pourquoi-)
- [Fonctionnalités](#fonctionnalités)
- [Démarrage rapide](#démarrage-rapide)
- [Utilisation détaillée](#utilisation-détaillée)
- [Exemple de sortie](#exemple-de-sortie)
- [Dépannage](#dépannage)
- [Exécution des tests & CI](#exécution-des-tests--ci)
- [Roadmap](#roadmap)
- [Licence & Auteur](#licence--auteur)

## Pourquoi ?
**Prouver rapidement et proprement qu’un site est joignable**, avec une sortie lisible par humain **et** exploitable par machine (JSON). Idéal pour : debug réseau, runbooks, CI/CD, support.

## Fonctionnalités
- Résolution **DNS → IP** (fallback `dig` → `getent`).
- Test **ICMP (ping)** optionnel.
- Vérification **TCP port 443** (ou autre via `-p`).
- **HEAD HTTP(S)** avec code et latence (via `curl -I -w ...`).
- Sortie **JSON** (fichier via `-o`), **codes de sortie** précis.
- **Makefile** (install, test, lint) & **GitHub Actions** (lint + smoke test).

## Démarrage rapide
```bash
./netproof.sh -d example.com
./netproof.sh -d example.com --no-icmp -o report.json -v
./netproof.sh -d example.com -p 443 --trace
```

### Prérequis
- Linux/WSL/macOS avec : `bash`, `curl`, `timeout` (coreutils), `dig` (ou `getent`), `ping`, `traceroute` (ou `tracepath`).
- Optionnel : `jq` (joli JSON), `shellcheck` (lint).

### Installation
```bash
sudo make install   # installe /usr/local/bin/netproof
netproof -d example.com
```

## Utilisation détaillée
```text
netproof v1.1.0
Usage: ./netproof.sh -d <domaine> [-p 443] [-o report.json] [--no-icmp] [--trace] [-v]
Options:
  -d, --domain   Domaine à tester (ex: example.com)
  -p, --port     Port TCP (défaut: 443)
  -o, --output   Chemin du fichier JSON de sortie
      --no-icmp  Désactiver le ping ICMP
      --trace    Lancer traceroute/tracepath si échec
  -v, --verbose  Mode verbeux
```

**Codes de sortie**
- `0` OK  ·  `1` DNS KO  ·  `2` ICMP KO  ·  `3` TCP KO  ·  `4` HTTP KO  ·  `5` Usage/Dépendance

## Exemple de sortie
```bash
./netproof.sh -d example.com --no-icmp -o examples/sample-report.json -v
```
```json
{
  "domain": "example.com",
  "ip": "93.184.216.34",
  "dns_ok": true,
  "icmp": {"enabled": false, "ok": false, "avg_ms": null, "loss_pct": null},
  "tcp": {"port": 443, "ok": true},
  "http": {"ok": true, "code": 200, "time_total_s": 0.12, "remote_ip": "93.184.216.34", "ssl_verify_result": "0"},
  "timestamp": "2025-08-24T15:45:12Z",
  "overall_ok": true
}
```

## Dépannage
- **DNS KO** → vérifier `/etc/resolv.conf`, résolveur, VPN/Proxy.
- **ICMP KO** → souvent filtré ; utiliser `--no-icmp` (non bloquant pour HTTPS).
- **TCP 443 KO** → firewall local (`ufw`/`iptables`) ou proxy d’entreprise.
- **HTTP ≠ 200** → redirections 301/302, erreurs 4xx/5xx ; tester `curl -v`.

## Exécution des tests & CI
```bash
make test          # lance tests/smoke.sh, produit examples/sample-report.json
make lint          # shellcheck (si installé)
```
- CI : workflow GitHub Actions (`.github/workflows/ci.yml`) → lint + smoke test + artefact JSON.

## Roadmap
- Support IPv6 explicite (`AAAA`, `-6/-4`).
- Détails TLS (jours avant expiration, CN/SAN).
- Option `--path /health` et choix HTTP/HTTPS.
- Fallback `mtr --report` en mode `--trace`.

## Licence & Auteur
- Licence : **MIT**
- Auteur : **DAVID HUGO VARELA DURAN**

> 💡 Astuce portfolio : ajoutez le badge CI ci-dessus et un tag `v1.1.0` : `git tag -a v1.1.0 -m "First public release" && git push origin v1.1.0`
