# Changelog

Semua perubahan penting di repo ini dicatat di sini, format ala Keep a Changelog.

## Kandidat update berikutnya
- Script autopanen: panen endpoint AI gratisan (OpenAI-compatible) secara berkala dan daftarkan otomatis sebagai provider 9Router. Arsitektur routing: **hasil panen sebagai jalur utama, Nous sebagai fallback** (kebalik dari asumsi awal).
- `herix-doctor`: script cek kesehatan all-in-one.
- Installer satu baris.

## [Unreleased]

### Diubah (BREAKING: migrasi tunnel Workers/D1 -> Cloudflare Zero Trust)
- Tunnel polling (Pages Functions + D1 + `tunnel-client.mjs`) DIHAPUS total:
  `tunnel/`, `tunnel-client.mjs`, `start-pages-tunnel.sh`. Alasan: limit 100.000
  request/hari Workers free tier + overhead polling; Zero Trust tunnel gratis
  tanpa limit request/bandwidth.
- `scripts/setup-tunnel.sh` ditulis ulang: install `cloudflared`, minta Tunnel
  Token (disimpan 600 di `~/.cloudflared-token`), minta public hostname,
  panduan tambah Public Hostname di dashboard Zero Trust, + tes koneksi 25 detik.
- `restart-tunnel.sh` ditulis ulang: restart `cloudflared tunnel run` (bracket
  trick agar tidak self-kill).
- `watchdog.sh` dan `scripts/start-all.sh` DIHAPUS — digantikan dua lapis
  pemantau baru (di bawah).
- `scripts/install.sh`: tambah install `cloudflared` ke `~/.local/bin`;
  versi 9Router di-pin (`NINE_ROUTER_VERSION`, default 0.5.95) agar reproducible.
- `.gitignore`: hapus entri wrangler/tunnel lama; tambah `.tunnel-hostname`.

### Ditambahkan
- `scripts/supervise.sh` — penjaga proses (loop tiap 30 detik, single-instance
  via flock): memastikan 9Router (127.0.0.1:20128), cloudflared, dan Hermes
  Telegram gateway selalu hidup; install ulang 9Router bila binary hilang.
- `scripts/monitor.sh` — pemantau kesehatan via cron tiap 10 menit: cek URL
  publik dari luar, pastikan supervise.sh hidup, install ulang 9Router bila
  perlu, jalankan gateway-watch.sh, auto-recovery + notifikasi Telegram
  opsional (hanya saat ada gangguan/pulih).
- `scripts/install-cron.sh` — pasang 3 cron idempoten: monitor (*/10),
  gateway-watch (*/5), supervise @reboot.
- `README.md` ditulis ulang jadi tutorial bahasa Indonesia langkah-demi-langkah
  untuk pemula (plus tabel perbandingan tunnel lama vs baru).

## Kandidat update berikutnya

### Ditambahkan
- `gateway-watch.sh` — watchdog anti-stall untuk Telegram gateway: 3 lapis deteksi (PID hilang, heartbeat event-loop basi, 0 aktivitas adapter Telegram 15 menit dengan konfirmasi 2 run), aturan keras hanya kill kalau tepat 1 kandidat PID, mode `DRY_RUN=1`, tidak menyentuh 9Router. Section dokumentasi di README.
- Section "Watchdog anti-stall gateway" di README + `gateway-watch.sh` di tabel layout file.
- `LICENSE` (MIT) — repo publik akhirnya punya lisensi biar orang berani fork/kontribusi.
- `scripts/start-all.sh` — starter idempoten semua komponen Herix (9Router, tunnel client, Telegram gateway); yang sudah jalan nggak disentuh. Siap dipanggil dari `@reboot` cron / systemd.
- Section "Auto-start" di README — contoh `@reboot` cron dan systemd user unit.
- `CHANGELOG.md` ini sendiri.

### Diperbaiki
- `restart-tunnel.sh`: supervisor `start-pages-tunnel.sh` ikut dibunuh sebelum restart — sebelumnya hanya client-nya yang dibunuh sehingga supervisor lama bisa menghidupkan client ganda.
- README: contoh `pgrep` di verifikasi & section watchdog diselaraskan ke pola exact `tunnel-client[.]mjs` (sebelumnya masih pola lama).
- README: diagram arsitektur "polling tiap ~400ms" → "long-poll ~20 detik", plus paragraf penjelasan kenapa long-poll ada (hemat jatah 100k request/hari Workers free tier).
- README: verifikasi `curl /dashboard` "harus 200" → "harus 200/307" (9Router balikin 307 redirect ke login, itu normal).
- `scripts/install.sh`: 9Router diinstall ke `$HOME/.npm-global` (konsisten sama PATH di script lain, aman tanpa root) + PATH dipersisten ke `~/.bashrc`.
- `scripts/install.sh`: flag manual `9router` disamakan dengan `start-9router.sh` (tambah `-l`).
- `restart-tunnel.sh`: pola kill dipersempit jadi exact `tunnel-client[.]mjs` — nggak ikut ngebunuh tunnel client lain di setup multi-tunnel.
- `tunnel-client.mjs`: komentar `TUNNEL_POLL_MS` diperjelas (sejak long-poll, ini cuma jeda tambahan antar long-poll, bukan interval polling utama).
- `watchdog.sh`: pola `pgrep` di-escape (`tunnel-client[.]mjs`) biar exact.
- `.gitignore`: tambah pola `.tunnel-key*` (varian key multi-tunnel nggak lolos ke-commit).
