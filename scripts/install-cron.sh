#!/usr/bin/env bash
# install-cron.sh — pasang jadwal otomatis (cron) untuk Hermuse.
#
# PENJELASAN SINGKAT (buat yang baru belajar):
#   "cron" adalah alarm bawaan Linux: "jalankan perintah ini tiap X menit".
#   Script ini memasang 3 alarm (idempoten = aman dijalankan berkali-kali):
#
#     */10 * * * *  monitor.sh        -> cek URL publik + auto-recovery (tiap 10 mnt)
#     */5  * * * *  gateway-watch.sh -> cegah bot Telegram macet diam-diam (tiap 5 mnt)
#     @reboot       supervise.sh      -> nyalakan penjaga proses setelah reboot
#
# Cara pakai:  bash scripts/install-cron.sh
# Lihat alarm: crontab -l
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MONITOR_LINE="*/10 * * * * /bin/bash $ROOT/scripts/monitor.sh >> $ROOT/monitor.log 2>&1"
WATCH_LINE="*/5 * * * * /bin/bash $ROOT/gateway-watch.sh >> $ROOT/gateway-watch.log 2>&1"
REBOOT_LINE="@reboot sleep 30 && /bin/bash $ROOT/scripts/supervise.sh >> $ROOT/supervisor.log 2>&1"

TMP="$(mktemp)"
crontab -l 2>/dev/null | grep -v -F "$ROOT/scripts/monitor.sh" | grep -v -F "$ROOT/gateway-watch.sh" | grep -v -F "$ROOT/scripts/supervise.sh" > "$TMP" || true
{
  cat "$TMP"
  echo "$MONITOR_LINE"
  echo "$WATCH_LINE"
  echo "$REBOOT_LINE"
} | crontab -
rm -f "$TMP"

echo "Cron terpasang:"
echo "  - monitor.sh tiap 10 menit"
echo "  - gateway-watch.sh tiap 5 menit"
echo "  - supervise.sh otomatis jalan setelah reboot"
echo "Cek dengan: crontab -l"
