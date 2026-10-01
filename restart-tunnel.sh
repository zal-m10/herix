#!/bin/bash
# Restart cloudflared (tunnel Zero Trust) secara detached.
#
# Pola "[c]" (bracket trick) punya dua fungsi:
#   1. tidak bunuh diri sendiri — regex "cloudflared" polos bisa cocok dengan
#      command line script ini sendiri saat pgrep/pkill berjalan;
#   2. presisi — hanya menyentuh proses cloudflared tunnel, bukan utilitas
#      cloudflared lain (mis. `cloudflared tunnel list`).
#
# Token dibaca dari $HOME/.cloudflared-token (mode 600).
# Dibuat oleh: bash scripts/setup-tunnel.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="${CLOUDFLARED_TOKEN_FILE:-$HOME/.cloudflared-token}"

[ -f "$TOKEN_FILE" ] || { echo "Token tidak ada di $TOKEN_FILE — jalankan bash scripts/setup-tunnel.sh dulu." >&2; exit 1; }

# bunuh tunnel lama (kalau ada), biarkan supervisor lain tidak tersentuh
pkill -f "cloudflared.*tunnel.*run" 2>/dev/null || true
sleep 3

setsid nohup cloudflared tunnel --no-autoupdate run \
  --token "$(cat "$TOKEN_FILE")" \
  > "$SCRIPT_DIR/cloudflared.log" 2>&1 < /dev/null &
echo "cloudflared tunnel restarted (pid $!)"
