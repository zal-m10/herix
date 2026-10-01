#!/usr/bin/env bash
# supervise.sh — PENJAGA PROSES Herix.
#
# PENJELASAN SINGKAT (buat yang baru belajar):
#   Program bisa mati sendiri (crash, kehabisan memori, server reboot).
#   Script ini jalan TERUS-MENERUS, dan setiap 30 detik mengecek:
#     1. 9Router ............ dashboard AI (127.0.0.1:20128)
#     2. cloudflared ........ terowongan ke Cloudflare (URL publik)
#     3. Hermes gateway ..... bot Telegram AI (hermes gateway run)
#   Kalau ada yang mati -> dinyalakan lagi otomatis. Kalau binary 9Router
#   hilang (mis. setelah OS di-reset) -> diinstall ulang otomatis.
#
# Cara pakai:
#   Jalan di foreground :  bash scripts/supervise.sh
#   Jalan di background :  setsid nohup bash scripts/supervise.sh >/dev/null 2>&1 < /dev/null &
#   Auto-start setelah reboot (lihat scripts/install-cron.sh untuk @reboot)
#
# Log: supervisor.log di folder ini.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG="$ROOT/supervisor.log"
LOCKF="$ROOT/.supervise.lock"
NINE_ROUTER_VERSION="${NINE_ROUTER_VERSION:-0.5.95}"
TOKEN_FILE="${CLOUDFLARED_TOKEN_FILE:-$HOME/.cloudflared-token}"

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# cegah dua supervisor jalan bersamaan
exec 9>"$LOCKF"
flock -n 9 || { echo "supervise.sh sudah jalan (lock aktif) — keluar." >&2; exit 1; }

log() { echo "[$(date -u '+%F %H:%M:%S')] $*" >> "$LOG"; }

ensure_9router() {
  # 1a. binary hilang? install ulang (kasus: OS/VM di-reset)
  if ! command -v 9router >/dev/null 2>&1; then
    log "9router tidak ditemukan — install ulang v${NINE_ROUTER_VERSION}..."
    mkdir -p "$HOME/.npm-global"
    if npm install -g --prefix "$HOME/.npm-global" "9router@${NINE_ROUTER_VERSION}" >>"$LOG" 2>&1; then
      log "9router v${NINE_ROUTER_VERSION} terinstall."
    else
      log "GAGAL install 9router — coba lagi 30 dtk."
      return 1
    fi
  fi
  # 1b. dashboard merespons? kalau tidak -> restart via supervisor bawaannya
  if ! curl -s -m 8 -o /dev/null http://127.0.0.1:20128/dashboard; then
    log "9Router mati — restart..."
    bash "$ROOT/restart-9router.sh" >>"$LOG" 2>&1
  fi
}

ensure_tunnel() {
  # tanpa token, tunnel tidak bisa jalan — beri peringatan sekali saja
  if [ ! -f "$TOKEN_FILE" ]; then
    [ -f "$ROOT/.supervise.warned-token" ] || {
      log "PERINGATAN: $TOKEN_FILE tidak ada — jalankan bash scripts/setup-tunnel.sh dulu."
      touch "$ROOT/.supervise.warned-token"
    }
    return 0
  fi
  rm -f "$ROOT/.supervise.warned-token"
  # pola "[c]" = bracket trick: pgrep tidak mencocokkan command line-nya sendiri
  if ! pgrep -f "cloudflared.*tunnel.*run" >/dev/null 2>&1; then
    log "cloudflared mati — restart tunnel..."
    setsid nohup cloudflared tunnel --no-autoupdate run \
      --token "$(cat "$TOKEN_FILE")" \
      >>"$ROOT/cloudflared.log" 2>&1 < /dev/null &
    log "cloudflared dinyalakan (pid $!)."
  fi
}

ensure_gateway() {
  # pola "[g]" = bracket trick, sama seperti di atas
  if ! pgrep -f "[g]ateway.*run" >/dev/null 2>&1; then
    log "Hermes gateway mati — restart..."
    bash "$ROOT/start-gateway.sh" >>"$LOG" 2>&1
  fi
}

log "=== supervise.sh mulai (pid $$) ==="
while true; do
  ensure_9router
  ensure_tunnel
  ensure_gateway
  sleep 30
done
