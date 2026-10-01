#!/usr/bin/env bash
# monitor.sh — PEMANTAU KESEHATAN Herix (dijalankan cron tiap 10 menit).
#
# PENJELASAN SINGKAT (buat yang baru belajar):
#   supervise.sh menjaga proses dari DALAM (tiap 30 detik). Script ini
#   mengecek dari LUAR seperti pengunjung biasa:
#     1. Apakah URL publik (https://hostname-kamu/login) bisa dibuka?
#     2. Apakah supervise.sh-nya sendiri masih hidup? (penjaga butuh penjaga)
#     3. Apakah binary 9Router masih ada?
#     4. Apakah Telegram gateway tidak stall? (via gateway-watch.sh)
#   Kalau URL publik mati -> coba pulihkan otomatis (restart 9Router /
#   cloudflared). Memberi tahu HANYA kalau benar-benar ada gangguan
#   (pulih kembali / masih gagal) — kalau sehat, diam saja.
#
# Notifikasi Telegram (opsional): set environment
#   TELEGRAM_BOT_TOKEN dan TELEGRAM_CHAT_ID sebelum cron berjalan.
#
# Cara pasang cron:  bash scripts/install-cron.sh
# Cara tes manual :  bash scripts/monitor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG="$ROOT/monitor.log"
LOCKF="$ROOT/.monitor.lock"
STATEF="$ROOT/.monitor-state"   # isi: OK / OUTAGE
HOSTNAME_FILE="$ROOT/.tunnel-hostname"
NINE_ROUTER_VERSION="${NINE_ROUTER_VERSION:-0.5.95}"

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

exec 9>"$LOCKF"
flock -n 9 || exit 0   # kalau run sebelumnya belum selesai, lewati saja

log() { echo "[$(date -u '+%F %H:%M:%S')] $*" >> "$LOG"; }

notify() { # $1 = pesan
  log "NOTIFY: $1"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -m 15 -o /dev/null \
      -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=[Herix monitor] $1" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" || true
  fi
}

# --- 1. Pastikan supervise.sh hidup (penjaga butuh penjaga) ---
if ! pgrep -f "supervise[.]sh" >/dev/null 2>&1; then
  log "supervise.sh mati — nyalakan lagi..."
  setsid nohup bash "$ROOT/scripts/supervise.sh" >/dev/null 2>&1 < /dev/null &
fi

# --- 2. Binary 9Router hilang? install ulang ---
if ! command -v 9router >/dev/null 2>&1; then
  log "binary 9router hilang — install ulang v${NINE_ROUTER_VERSION}..."
  mkdir -p "$HOME/.npm-global"
  npm install -g --prefix "$HOME/.npm-global" "9router@${NINE_ROUTER_VERSION}" >>"$LOG" 2>&1 || \
    log "GAGAL install 9router."
fi

# --- 3. Cek URL publik ---
HOSTNAME="$(cat "$HOSTNAME_FILE" 2>/dev/null || true)"
PUBLIC_OK=0
if [ -n "$HOSTNAME" ]; then
  CODE="$(curl -s -m 20 -o /dev/null -w "%{http_code}" "https://${HOSTNAME}/login" || true)"
  [ "$CODE" = "200" ] && PUBLIC_OK=1
else
  log "PERINGATAN: $HOSTNAME_FILE tidak ada — lewati cek URL publik."
  PUBLIC_OK=1  # jangan false alarm kalau hostname belum diset
fi

if [ "$PUBLIC_OK" = "1" ]; then
  # Sehat: kalau sebelumnya OUTAGE, catat pulih
  if [ -f "$STATEF" ] && [ "$(cat "$STATEF")" = "OUTAGE" ]; then
    echo "OK" > "$STATEF"
    notify "URL publik pulih kembali: https://${HOSTNAME}/login"
  fi
else
  log "URL publik MATI (https://${HOSTNAME}/login) — coba pulihkan..."
  # 3a. 9Router lokal?
  if ! curl -s -m 8 -o /dev/null http://127.0.0.1:20128/dashboard; then
    log "9Router lokal mati — restart..."
    bash "$ROOT/restart-9router.sh" >>"$LOG" 2>&1
    sleep 10
  fi
  # 3b. Tunnel?
  log "restart cloudflared..."
  bash "$ROOT/restart-tunnel.sh" >>"$LOG" 2>&1
  sleep 15
  # 3c. Cek lagi
  CODE2="$(curl -s -m 20 -o /dev/null -w "%{http_code}" "https://${HOSTNAME}/login" || true)"
  if [ "$CODE2" = "200" ]; then
    echo "OK" > "$STATEF"
    notify "Gangguan terdeteksi tapi BERHASIL dipulihkan otomatis. URL: https://${HOSTNAME}/login"
  else
    echo "OUTAGE" > "$STATEF"
    notify "GANGGUAN: URL publik masih mati setelah auto-recovery. Cek manual: $LOG"
  fi
fi

# --- 4. Anti-stall Telegram gateway (deteksi macet diam-diam) ---
if [ -x "$ROOT/gateway-watch.sh" ]; then
  bash "$ROOT/gateway-watch.sh" >>"$LOG" 2>&1 || \
    log "gateway-watch.sh menemukan masalah — lihat gateway-watch.log"
fi

# Sehat total dan tidak ada perubahan status: diam (tidak log apa-apa)
exit 0
