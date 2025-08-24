#!/usr/bin/env bash
set -euo pipefail
# netproof: prouve la joignabilité d’un site (DNS -> IP -> TCP:443 -> HTTP)
# Codes de sortie: 0 OK, 1 DNS, 2 ICMP, 3 TCP, 4 HTTP, 5 usage/dépendances

VERSION="1.1.0"

log()  { printf '%s\n' "$*" >&2; }
info() { [ "${VERBOSE:-0}" -eq 1 ] && log "[INFO] $*"; }
ok()   { log "[OK] $*"; }
err()  { log "[ERR] $*"; }

DOMAIN=""
PORT=443
OUTPUT_JSON=""
DO_ICMP=1
DO_TRACE=0
VERBOSE=0

usage() {
  cat <<H
netproof v$VERSION
Usage: $0 -d <domaine> [-p 443] [-o report.json] [--no-icmp] [--trace] [-v]
Options:
  -d, --domain   Domaine à tester (ex: example.com)
  -p, --port     Port TCP (défaut: 443)
  -o, --output   Chemin fichier JSON de sortie
      --no-icmp  Désactiver le ping ICMP
      --trace    Lancer traceroute/tracepath en cas d'échec réseau
  -v, --verbose  Mode verbeux
  -h, --help     Aide
H
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Dépendance manquante: $1"; exit 5; }; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--domain) DOMAIN="$2"; shift 2;;
      -p|--port)   PORT="$2"; shift 2;;
      -o|--output) OUTPUT_JSON="$2"; shift 2;;
      --no-icmp)   DO_ICMP=0; shift;;
      --trace)     DO_TRACE=1; shift;;
      -v|--verbose) VERBOSE=1; shift;;
      -h|--help)   usage; exit 0;;
      *) err "Option inconnue: $1"; usage; exit 5;;
    esac
  done
  [[ -n "${DOMAIN}" ]] || { err "Le domaine est requis (-d)"; usage; exit 5; }
}

dns_resolve() {
  local dom="$1" ip=""
  if command -v dig >/dev/null 2>&1; then
    ip="$(dig +short A "$dom" | head -n1 || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(getent ahostsv4 "$dom" | awk '{print $1; exit}' || true)"
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

icmp_ping() {
  local target="$1" count=4
  if ping -c "$count" -n "$target" >/tmp/netproof_ping.$$ 2>/dev/null; then :;
  elif ping -c "$count" "$target" >/tmp/netproof_ping.$$ 2>/dev/null; then :;
  else
    return 1
  fi
  local avg loss
  avg="$(awk -F'/' '/round-trip|rtt/ {print $5}' /tmp/netproof_ping.$$ 2>/dev/null || true)"
  if [[ -z "$avg" ]]; then
    avg="$(awk -F'=' '/min\/avg\/max/ {split($2,a,"/"); print a[2]}' /tmp/netproof_ping.$$ 2>/dev/null || true)"
  fi
  loss="$(awk -F',' '/packet loss/ {gsub(/[% ]/,"",$3); print $3}' /tmp/netproof_ping.$$ 2>/dev/null || true)"
  rm -f /tmp/netproof_ping.$$
  echo "${avg:-} ${loss:-}"
}

tcp_check() {
  local host="$1" port="$2"
  if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
    return 0
  fi
  if curl -Is --connect-timeout 5 "https://$host:$port" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

http_head() {
  local url="$1"
  local hdr="/tmp/netproof_hdr.$$"
  local meta="/tmp/netproof_meta.$$"
  # -I écrit les entêtes dans $hdr ; -w écrit les métriques sur stdout → redirigé dans $meta
  if ! curl -I -sS -o "$hdr" -w "%{http_code} %{time_total} %{remote_ip} %{ssl_verify_result}\n" "$url" > "$meta"; then
    rm -f "$hdr" "$meta"; return 1
  fi
  local code time ip ssl
  read -r code time ip ssl < "$meta" || true
  rm -f "$meta" "$hdr"
  [[ -n "${code:-}" ]] || return 1
  echo "$code" "$time" "$ip" "$ssl"
}

timestamp_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

write_json() {
  # Sanitize nombres: null si vide/NaN
  local avg_json loss_json
  if [[ -z "${icmp_avg:-}" || "${icmp_avg:-}" == "NaN" ]]; then avg_json=null; else avg_json="$icmp_avg"; fi
  if [[ -z "${icmp_loss:-}" || "${icmp_loss:-}" == "NaN" ]]; then loss_json=null; else loss_json="$icmp_loss"; fi

  local overall="false"
  if [[ "${dns_ok:-false}" == "true" && ( "$DO_ICMP" -eq 0 || "${icmp_ok:-false}" == "true" ) && "${tcp_ok:-false}" == "true" && "${http_ok:-false}" == "true" ]]; then
    overall="true"
  fi

  local json
  json=$(cat <<J
{
  "domain": "${DOMAIN}",
  "ip": "${ip:-}",
  "dns_ok": ${dns_ok:-false},
  "icmp": {"enabled": $( [[ "$DO_ICMP" -eq 1 ]] && echo true || echo false ), "ok": ${icmp_ok:-false}, "avg_ms": ${avg_json}, "loss_pct": ${loss_json}},
  "tcp": {"port": ${PORT}, "ok": ${tcp_ok:-false}},
  "http": {"ok": ${http_ok:-false}, "code": ${http_code:-0}, "time_total_s": ${http_time:-0}, "remote_ip": "${http_ip:-}", "ssl_verify_result": "${ssl_rc:-}"},
  "timestamp": "$(timestamp_utc)",
  "overall_ok": ${overall}
}
J
)
  if [[ -n "${OUTPUT_JSON}" ]]; then
    printf '%s\n' "$json" > "$OUTPUT_JSON"
    info "JSON -> $OUTPUT_JSON"
  else
    printf '%s\n' "$json"
  fi
}

main() {
  parse_args "$@"
  need_cmd curl
  need_cmd timeout
  command -v traceroute >/dev/null 2>&1 || command -v tracepath >/dev/null 2>&1 || true

  local ip dns_ok=false icmp_ok=false icmp_avg="" icmp_loss=""
  local tcp_ok=false http_ok=false http_code=0 http_time="0" http_ip="" ssl_rc=""

  ip="$(dns_resolve "$DOMAIN" || true)"
  if [[ -n "$ip" ]]; then
    dns_ok=true; info "DNS -> $ip"
  else
    err "DNS KO pour $DOMAIN"; write_json; exit 1
  fi

  if [[ "$DO_ICMP" -eq 1 ]]; then
    if out="$(icmp_ping "$DOMAIN" || true)"; then
      icmp_ok=true
      icmp_avg="$(awk '{print $1}' <<<"$out")"
      icmp_loss="$(awk '{print $2}' <<<"$out")"
      info "PING avg=${icmp_avg:-?}ms loss=${icmp_loss:-?}%"
    else
      err "PING KO (ICMP filtré ?)"
      [[ "$DO_TRACE" -eq 1 ]] && { (command -v traceroute >/dev/null && traceroute -n "$DOMAIN") || (command -v tracepath >/dev/null && tracepath -n "$DOMAIN") || true; }
      write_json; exit 2
    fi
  fi

  if tcp_check "$DOMAIN" "$PORT"; then
    tcp_ok=true; info "TCP $PORT -> OPEN"
  else
    err "TCP $PORT KO (firewall/route ?)"
    [[ "$DO_TRACE" -eq 1 ]] && { (command -v traceroute >/dev/null && traceroute -n "$DOMAIN") || (command -v tracepath >/dev/null && tracepath -n "$DOMAIN") || true; }
    write_json; exit 3
  fi

  read -r http_code http_time http_ip ssl_rc < <(http_head "https://$DOMAIN:$PORT" || true)
  if [[ -n "${http_code:-}" && "${http_code}" != "000" ]]; then
    http_ok=true; info "HTTP ${http_code} in ${http_time}s ip=${http_ip} (ssl_rc=${ssl_rc})"
  else
    err "HTTP KO (aucune entête reçue)"; write_json; exit 4
  fi

  ok "$DOMAIN is reachable over HTTPS ✅"
  write_json; exit 0
}

main "$@"
