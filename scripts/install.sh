#!/usr/bin/env bash
# Install otomatis: Hermes Agent + Node.js + 9Router di VM Linux (Debian/Ubuntu).
# Dijalankan sebagai user biasa (bukan root). Tidak butuh input interaktif
# kecuali saat login provider nanti (langkah manual setelah script selesai).
#
# Cara pakai:
#   bash scripts/install.sh
set -euo pipefail

log() { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }

# Versi 9Router yang dipin agar instalasi reproducible (tidak berubah-ubah
# mengikuti rilis terbaru yang belum tentu kompatibel).
NINE_ROUTER_VERSION="${NINE_ROUTER_VERSION:-0.5.95}"

# --- 1. Cek OS ---
if ! command -v apt-get >/dev/null 2>&1; then
  warn "Script ini untuk Debian/Ubuntu (butuh apt-get). Install manual untuk distro lain."
  exit 1
fi

# --- 2. Dependensi dasar ---
log "Menginstall dependensi dasar (git, curl, tar)..."
sudo apt-get update -y
sudo apt-get install -y git curl tar ca-certificates

# --- 3. Node.js LTS (dibutuhkan 9Router via npm) ---
if ! command -v node >/dev/null 2>&1; then
  log "Menginstall Node.js LTS via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  log "Node.js sudah ada: $(node --version)"
fi

# --- 4. Hermes Agent (installer resmi Nous Research) ---
if ! command -v hermes >/dev/null 2>&1; then
  log "Menginstall Hermes Agent..."
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
  # shellcheck disable=SC1090
  source ~/.bashrc 2>/dev/null || true
  export PATH="$HOME/.local/bin:$PATH"
else
  log "Hermes sudah ada: $(hermes --version 2>/dev/null || echo '?')"
fi

# --- 5. 9Router (paket npm, versi di-pin) ---
# Install ke $HOME/.npm-global agar konsisten dengan PATH di script lain
# (start-9router.sh) dan tetap aman tanpa akses root.
if ! command -v 9router >/dev/null 2>&1; then
  log "Menginstall 9Router v${NINE_ROUTER_VERSION}..."
  mkdir -p "$HOME/.npm-global"
  npm install -g --prefix "$HOME/.npm-global" "9router@${NINE_ROUTER_VERSION}"
  export PATH="$HOME/.npm-global/bin:$PATH"
  # pastikan persisten untuk shell berikutnya
  grep -q '.npm-global/bin' ~/.bashrc 2>/dev/null || \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
else
  log "9Router sudah ada: $(9router --version 2>/dev/null || echo '?')"
fi

# --- 5b. cloudflared (tunnel Zero Trust) ---
# Diinstall ke ~/.local/bin (tanpa root). Dipakai setup-tunnel.sh,
# restart-tunnel.sh, dan supervise.sh.
if ! command -v cloudflared >/dev/null 2>&1; then
  log "Menginstall cloudflared..."
  mkdir -p "$HOME/.local/bin"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)        CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) log "Arsitektur $ARCH tidak dikenali — lewati install cloudflared (install manual nanti)."; CF_ARCH="" ;;
  esac
  if [ -n "$CF_ARCH" ]; then
    curl -fsSL -o "$HOME/.local/bin/cloudflared" \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    chmod +x "$HOME/.local/bin/cloudflared"
    export PATH="$HOME/.local/bin:$PATH"
    grep -q '.local/bin' ~/.bashrc 2>/dev/null || \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    log "cloudflared terinstall."
  fi
else
  log "cloudflared sudah ada."
fi

# --- 6. Verifikasi ---
log "Verifikasi instalasi Hermes..."
export PATH="$HOME/.local/bin:$PATH"
if hermes doctor; then
  log "hermes doctor: OK"
else
  warn "hermes doctor menemukan masalah — lihat output di atas."
fi

cat << 'EOF'

============================================================
 Instalasi selesai. Langkah manual berikutnya:
  1. hermes setup --portal     # login provider model (OAuth)
     atau: hermes model        # pilih provider/model
  2. Buat bot Telegram via @BotFather, catat tokennya.
  3. Dapatkan numeric ID via @userinfobot.
  4. hermes gateway setup       # isi token bot + allowlist ID
  5. bash scripts/setup-tunnel.sh   # buat tunnel Zero Trust (butuh Tunnel Token)
  6. Ikuti README.md bagian "Menyalakan semuanya"
============================================================
EOF
