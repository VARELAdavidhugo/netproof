# netproof — Vérifier la joignabilité d’un site (DNS → IP → TCP:443 → HTTP)

## 🎯 Objectif
Prouver automatiquement (et horodaté) qu’un site est joignable :
1) Résolution DNS → IP  
2) Connectivité IP (ICMP/ping, optionnelle)  
3) Port TCP 443 ouvert  
4) Réponse HTTP(S) avec code + latence  

Sortie **texte** lisible + **JSON** (intégrable en CI).

---

## ⚙️ Prérequis
Linux/WSL/macOS avec :
- `bash`
- `curl`
- `dig` (ou `getent`)
- `ping`
- `traceroute` (ou `tracepath`)
- `timeout` (coreutils)

Optionnel :
- `jq` → joli affichage JSON
- `shellcheck` → lint Bash

---

## 🚀 Utilisation
```bash
./netproof.sh -d example.com
./netproof.sh -d example.com -o report.json --no-icmp -v
./netproof.sh -d example.com -p 443 --trace
