#!/usr/bin/env bash
# Setup Cloudflare Zero Trust Tunnel untuk 9Router.
#
# PENJELASAN SINGKAT (buat yang baru belajar):
#   9Router hanya jalan di localhost (127.0.0.1:20128) — tidak bisa diakses
#   dari internet. "Tunnel" adalah terowongan aman dari komputermu ke
#   Cloudflare: Cloudflare memberi alamat publik (https://domain-kamu...)
#   dan setiap pengunjung alamat itu diteruskan lewat terowongan ke 9Router.
#   Program yang membuat terowongan ini namanya "cloudflared".
#
# Yang script ini lakukan:
#   1. Install cloudflared (kalau belum ada) ke ~/.local/bin
#   2. Minta Tunnel Token dari kamu (dibuat sekali di dashboard Cloudflare),
#      simpan di ~/.cloudflared-token (mode 600 = hanya kamu yang bisa baca)
#   3. Minta public hostname (mis. ai.domainkamu.my.id), simpan di .tunnel-hostname
#   4. Tes cepat: jalankan tunnel 25 detik, cek URL publiknya hidup atau tidak
#
# Token dipakai transient saja saat menjalankan cloudflared — tidak pernah
# di-commit ke git (sudah ada di .gitignore).
#
# Cara pakai:
#   bash scripts/setup-tunnel.sh
#   (atau non-interaktif: TUNNEL_TOKEN="..." TUNNEL_HOSTNAME="..." bash scripts/setup-tunnel.sh)
set -euo pipefail

log()  { printf '\033[1;32m[tunnel-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[tunnel-setup]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[tunnel-setup]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
TOKEN_FILE="$HOME/.cloudflared-token"
HOSTNAME_FILE="$ROOT/.tunnel-hostname"

# --- 1. Install cloudflared ---
if ! command -v cloudflared >/dev/null 2>&1; then
  log "cloudflared belum ada — menginstall ke ~/.local/bin ..."
  mkdir -p "$HOME/.local/bin"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) die "Arsitektur $ARCH belum didukung script ini. Install cloudflared manual: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" ;;
  esac
  curl -fsSL -o "$HOME/.local/bin/cloudflared" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
  chmod +x "$HOME/.local/bin/cloudflared"
  export PATH="$HOME/.local/bin:$PATH"
  grep -q '.local/bin' ~/.bashrc 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  log "cloudflared terinstall: $(cloudflared --version 2>/dev/null | head -1)"
else
  log "cloudflared sudah ada: $(cloudflared --version 2>/dev/null | head -1)"
fi

# --- 2. Tunnel Token ---
# Dibuat di dashboard Cloudflare: Zero Trust -> Networks -> Tunnels
# -> Create a tunnel -> salin tokennya. Lihat README bagian "Buat tunnel".
TOKEN="${TUNNEL_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
  warn "Token sudah ada di $TOKEN_FILE — pakai yang lama."
  warn "Mau ganti? Hapus file-nya dulu: rm $TOKEN_FILE"
  TOKEN="__EXISTING__"
fi
if [ ! -f "$TOKEN_FILE" ]; then
  if [ -z "${TUNNEL_TOKEN:-}" ]; then
    echo ""
    echo "Tempel Tunnel Token dari dashboard Cloudflare (Zero Trust -> Networks -> Tunnels):"
    echo "(input disembunyikan, klik kanan -> paste, lalu Enter)"
    read -rs TOKEN_INPUT
    echo ""
    [ -n "$TOKEN_INPUT" ] || die "Token kosong — batal."
    TOKEN="$TOKEN_INPUT"
  fi
  printf '%s' "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  log "Token disimpan di $TOKEN_FILE (mode 600)."
fi

# --- 3. Public hostname ---
HOSTNAME="${TUNNEL_HOSTNAME:-}"
if [ -z "$HOSTNAME" ] && [ -f "$HOSTNAME_FILE" ]; then
  HOSTNAME="$(cat "$HOSTNAME_FILE")"
  warn "Hostname sudah ada: $HOSTNAME — pakai yang lama."
fi
if [ -z "$HOSTNAME" ]; then
  if [ -n "${TUNNEL_HOSTNAME:-}" ]; then
    HOSTNAME="$TUNNEL_HOSTNAME"
  else
    echo ""
    echo "Ketik public hostname tunnel (yang kamu daftarkan di dashboard), contoh:"
    echo "  ai.domainkamu.my.id"
    read -r HOSTNAME
    [ -n "$HOSTNAME" ] || die "Hostname kosong — batal."
  fi
  printf '%s' "$HOSTNAME" > "$HOSTNAME_FILE"
  log "Hostname disimpan di $HOSTNAME_FILE."
fi

# --- 4. Tes cepat ---
cat << EOF

============================================================
 LANGKAH DASHBOARD (sekali saja, kalau belum):
  1. Buka https://one.dash.cloudflare.com -> Zero Trust
     -> Networks -> Tunnels -> pilih tunnel kamu
  2. Tab "Public Hostname" -> Add a public hostname
     - Subdomain + Domain : $HOSTNAME
     - Service Type       : HTTP
     - URL                : 127.0.0.1:20128
  3. Save. Tunggu ~30 detik.
============================================================
EOF
echo ""
read -r -p "Sudah tambah Public Hostname di dashboard? Tes sekarang? [Y/n] " ANS
ANS="${ANS:-Y}"
if [[ "$ANS" =~ ^[Yy]$ ]]; then
  log "Menjalankan cloudflared 25 detik untuk tes..."
  cloudflared tunnel --no-autoupdate run --token "$(cat "$TOKEN_FILE")" \
    > "$ROOT/cloudflared-test.log" 2>&1 &
  TEST_PID=$!
  sleep 12
  if curl -s -m 15 -o /dev/null -w "%{http_code}" "https://${HOSTNAME}/login" | grep -q "200"; then
    log "SUKSES! https://${HOSTNAME}/login bisa diakses (HTTP 200)."
  else
    warn "Belum bisa diakses. Kemungkinan: Public Hostname belum disimpan di"
    warn "dashboard, atau DNS-nya masih propagasi. Cek log: $ROOT/cloudflared-test.log"
  fi
  kill "$TEST_PID" 2>/dev/null || true
  sleep 2
fi

cat << EOF

============================================================
 Selesai! Tunnel siap dipakai.

 Langkah berikutnya (dari root repo ini):
  1. Pastikan 9Router jalan : bash restart-9router.sh
  2. Nyalakan penjaga proses: bash scripts/supervise.sh
     (atau: setsid nohup bash scripts/supervise.sh >/dev/null 2>&1 < /dev/null &)
  3. Pasang monitor cron     : bash scripts/install-cron.sh
  4. Buka dashboard          : https://${HOSTNAME}/login
  5. PENTING: ganti password dashboard 9Router dari default!
     echo -n 'password-baru' > .dashboard-pw && chmod 600 .dashboard-pw
============================================================
EOF
