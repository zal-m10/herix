# Hermuse — edisi Zero Trust Tunnel

**Hermuse = Hermes + Muse.** Repo ini berisi script dan panduan untuk menjalankan **bot Telegram AI pribadi** (Hermes Agent dari Nous Research) + **dashboard model AI** (9Router) di server sendiri, online 24/7.

> **Versi modifikasi** dari [imkofty/Hermuse](https://github.com/imkofty/Hermuse) (lisensi MIT).
> Perubahan utama: tunnel dashboard **diganti total** dari Cloudflare Workers + D1
> menjadi **Cloudflare Zero Trust Tunnel** — gratis, tanpa limit request, dan
> kode yang dihapus lebih banyak daripada yang ditambah. Lihat
> [Perbandingan tunnel](#perbandingan-tunnel-lama-vs-baru).

**Hasil akhirnya:** kamu chat dengan AI pribadimu lewat Telegram kapan saja, dan
bisa buka dashboard model dari browser lewat alamat seperti
`https://ai.domainkamu.my.id`.

---

## Daftar isi

- [Analogi cara kerja](#analogi-cara-kerja)
- [Perbandingan tunnel lama vs baru](#perbandingan-tunnel-lama-vs-baru)
- [Yang kamu butuhkan](#yang-kamu-butuhkan)
- [Langkah 1 — Install semuanya](#langkah-1--install-semuanya)
- [Langkah 2 — Buat Tunnel Token di Cloudflare](#langkah-2--buat-tunnel-token-di-cloudflare)
- [Langkah 3 — Pasang tunnel](#langkah-3--pasang-tunnel)
- [Langkah 4 — Ganti password dashboard](#langkah-4--ganti-password-dashboard-wajib)
- [Langkah 5 — Sambungkan bot Telegram](#langkah-5--sambungkan-bot-telegram)
- [Langkah 6 — Nyalakan penjaga proses](#langkah-6--nyalakan-penjaga-proses)
- [Langkah 7 — Pasang monitor otomatis (cron)](#langkah-7--pasang-monitor-otomatis-cron)
- [Langkah 8 — Verifikasi](#langkah-8--verifikasi)
- [Dua lapis pemantau](#dua-lapis-pemantau)
- [Perintah sehari-hari](#perintah-sehari-hari)
- [Kalau ada masalah (troubleshooting)](#kalau-ada-masalah-troubleshooting)
- [Keamanan](#keamanan)
- [Layout file](#layout-file)

---

## Analogi cara kerja

Bayangkan komputermu (VPS) adalah **rumah**, dan 9Router adalah **TV di ruang
tengah** — hanya orang di dalam rumah yang bisa menonton.

**Tunnel** itu seperti **terowongan rahasia** dari rumahmu ke menara Cloudflare.
Cloudflare lalu memasang **papan nama** (alamat publik, mis.
`https://ai.domainkamu.my.id`). Siapa pun yang datang ke papan nama itu,
diteruskan lewat terowongan langsung ke TV di ruang tengah — tanpa kamu perlu
membuka pintu rumah (tanpa buka port / setting router).

Alurnya:

```
Kamu (Telegram)                    VPS kamu
    │  chat                    ┌─────────────────────────┐
    ▼                          │ Hermes gateway         │──▶ model AI
Telegram ──polling──▶          │ (bot Telegram)        │      (Nous / 9Router)
                               └─────────────────────────┘

Kamu (browser)                     VPS kamu
    │ https                    ┌─────────────────────────┐
    ▼                          │ 9Router                 │
https://ai.domainkamu.my.id ──▶│ (127.0.0.1:20128)      │
    ▲                          └─────────────────────────┘
    │                                   ▲
    │              terowongan           │
    └────── Cloudflare ◀── cloudflared ──┘
              (Zero Trust Tunnel)
```

Istilah yang akan sering muncul:

| Istilah | Artinya sederhana |
|---|---|
| VPS | Komputer sewaan di internet yang jalan 24 jam (pengganti laptop yang dimatikan) |
| Domain | Nama alamat, mis. `domainkamu.my.id` (beli di Niagahoster/Domainesia/dll, ~Rp 100–150rb/tahun) |
| DNS | "Buku telepon" internet: mengubah nama domain jadi alamat komputer |
| Tunnel | Terowongan aman dari VPS ke Cloudflare (dibuat oleh program `cloudflared`) |
| Tunnel Token | Kunci rahasia satu tunnel — seperti password khusus terowonganmu |
| Public Hostname | Alamat publik yang tampil di browser, mis. `ai.domainkamu.my.id` |
| cron | "Alarm" bawaan Linux: menjalankan perintah otomatis tiap X menit |

---

## Perbandingan tunnel lama vs baru

|  | Tunnel lama (dihapus) | Tunnel baru (dipakai sekarang) |
|---|---|---|
| Teknologi | Cloudflare Pages Functions + D1 | Cloudflare Zero Trust Tunnel (`cloudflared`) |
| Limit gratis | **100.000 request/hari**, lewat = error | **Tanpa limit** request & bandwidth |
| Cara kerja | Request dititip di database (D1), diambil tiap ~20 detik (long-poll) | Koneksi langsung persistent, request diteruskan seketika |
| Latensi | Lebih tinggi (antre + poll) | Lebih rendah |
| Butuh domain sendiri | Tidak (pakai `*.pages.dev`) | **Ya**, domain harus terdaftar di Cloudflare |
| File kode | 5 file (functions + client + skema) | 1 program (`cloudflared`) + 1 script setup |

---

## Yang kamu butuhkan

1. **VPS Linux** — Ubuntu 22.04/24.04, 2 vCPU / 4 GB RAM cukup.
   (Contoh: Niagahoster, Biznet Gio, IDCloudHost, DigitalOcean — pilih yang
   termurah, sekitar Rp 50–100rb/bulan.)
2. **Domain** yang nameserver-nya sudah diarahkan ke Cloudflare
   (daftar gratis di [dash.cloudflare.com](https://dash.cloudflare.com) → Add domain → ikuti panduannya ganti nameserver).
3. **Akun Cloudflare gratis** — untuk Zero Trust Tunnel.
4. **Bot Telegram** — chat ke [@BotFather](https://t.me/BotFather), kirim
   `/newbot`, catat tokennya. Cari tahu ID Telegram-mu lewat
   [@userinfobot](https://t.me/userinfobot).
5. Akses terminal ke VPS (SSH). Belum pernah pakai SSH? Cukup tahu satu
   perintah: `ssh username@ip-vps-kamu`.

---

## Langkah 1 — Install semuanya

Di VPS, jalankan:

```bash
git clone https://github.com/<akun-kamu>/hermuse-zerotrust
cd hermuse-zerotrust
bash scripts/install.sh
```

Script ini menginstall otomatis: Node.js, Hermes Agent, 9Router (versi di-pin
agar tidak berubah-ubah), dan `cloudflared`. Di akhir ada langkah manual —
lakukan **nanti** setelah Langkah 3 (disarankan urutan tutorial ini).

> Semua script dijalankan sebagai **user biasa, bukan root**. Kalau ada
> perintah yang butuh root, script akan memintanya sendiri via `sudo`.

---

## Langkah 2 — Buat Tunnel Token di Cloudflare

Token ini cukup dibuat **sekali**. Buka di browser:

1. Masuk ke [one.dash.cloudflare.com](https://one.dash.cloudflare.com)
2. Menu kiri → **Networks** → **Tunnels** → **Create a tunnel**
3. Pilih **Cloudflared**, beri nama mis. `hermuse`, klik **Save tunnel**
4. Di halaman berikutnya ada **kolom token** (string panjang) → **salin**,
   simpan sementara di notepad. **Jangan dibagikan ke siapa pun.**
5. Klik **Save** (atau tutup halaman — tokennya yang penting sudah disalin)

> Catatan: di halaman ini Cloudflare juga menawarkan "Install and run a
> connector" — **lewati saja**, connector-nya akan dijalankan oleh script
> kita di Langkah 3.

---

## Langkah 3 — Pasang tunnel

Kembali ke terminal VPS, dari folder repo:

```bash
bash scripts/setup-tunnel.sh
```

Script akan:
1. Memastikan `cloudflared` terinstall.
2. Meminta **Tunnel Token** (tempel yang disalin di Langkah 2 — ketikannya
   disembunyikan, klik kanan → paste → Enter). Disimpan di
   `~/.cloudflared-token` dengan mode 600 (hanya kamu yang bisa baca).
3. Meminta **public hostname**, contoh: `ai.domainkamu.my.id`.
4. Menampilkan panduan menambahkan **Public Hostname** di dashboard —
   lakukan ini sekarang di browser:
   - [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → Networks →
     Tunnels → pilih tunnel `hermuse` → tab **Public Hostname** →
     **Add a public hostname**
   - Hostname: `ai` + domain kamu (hasilnya `ai.domainkamu.my.id`)
   - Service Type: **HTTP** — URL: **`127.0.0.1:20128`**
   - **Save**, tunggu ~30 detik.
5. Mengetes: menjalankan tunnel 25 detik lalu membuka
   `https://ai.domainkamu.my.id/login`. Kalau dapat **HTTP 200 = berhasil**.

---

## Langkah 4 — Ganti password dashboard (WAJIB)

9Router punya password default. Ganti sekarang juga:

```bash
echo -n 'password-baru-yang-kuat' > .dashboard-pw && chmod 600 .dashboard-pw
bash restart-9router.sh
```

> Aturan file rahasia: **tidak pernah** ditulis langsung di script, hanya di
> file khusus dengan `chmod 600`. File-file ini sudah masuk
> `.gitignore` jadi tidak akan ke-commit.

---

## Langkah 5 — Sambungkan bot Telegram

```bash
hermes setup --portal     # login provider model (ikuti OAuth di browser)
hermes gateway setup      # isi token bot dari @BotFather + ID Telegram-mu (allowlist)
```

Tes gateway-nya jalan:

```bash
bash start-gateway.sh
# tunggu ~30 detik, lalu cek log:
grep -m1 "Connected to Telegram" gateway.log && echo "BOT TERHUBUNG"
```

Chat bot-mu di Telegram — harusnya dibalas AI.

---

## Langkah 6 — Nyalakan penjaga proses

```bash
setsid nohup bash scripts/supervise.sh >/dev/null 2>&1 < /dev/null &
```

`supervise.sh` jalan terus dan **tiap 30 detik** memastikan tiga komponen
hidup: 9Router, tunnel `cloudflared`, dan Hermes gateway. Yang mati
dinyalakan lagi otomatis; kalau binary 9Router hilang (mis. setelah OS
di-reset) akan diinstall ulang sendiri. Log: `supervisor.log`.

Cek dia jalan:

```bash
pgrep -af "supervise[.]sh" && echo "PENJAGA AKTIF"
```

---

## Langkah 7 — Pasang monitor otomatis (cron)

```bash
bash scripts/install-cron.sh
```

Ini memasang 3 "alarm" Linux (aman dijalankan berkali-kali):

| Alarm | Kerja |
|---|---|
| Tiap 10 menit → `scripts/monitor.sh` | Buka URL publik **seperti pengunjung biasa**. Kalau mati → pulihkan otomatis (restart 9Router/tunnel). Memberi tahu hanya kalau benar-benar ada gangguan. |
| Tiap 5 menit → `gateway-watch.sh` | Deteksi bot Telegram yang **macet diam-diam** (proses hidup tapi tidak membalas) lalu restart. |
| Saat reboot → `scripts/supervise.sh` | Nyalakan penjaga proses 30 detik setelah VPS menyala. |

Lihat alarm yang terpasang: `crontab -l`

> **Notifikasi Telegram (opsional):** agar monitor mengabarimu saat ada
> gangguan, tambahkan dua baris ini di atas cron (edit via `crontab -e`):
> ```
> TELEGRAM_BOT_TOKEN=123456:ABC...
> TELEGRAM_CHAT_ID=987654321
> ```
> (Pakai bot dan ID yang sama seperti Langkah 5.)

---

## Langkah 8 — Verifikasi

Jalankan cek terakhir ini — semua harus OK:

```bash
echo "--- 9Router lokal ---"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:20128/login

echo "--- URL publik ---"
curl -s -o /dev/null -w "%{http_code}\n" https://$(cat .tunnel-hostname)/login

echo "--- Proses ---"
pgrep -f "9router -p" >/dev/null && echo "OK 9Router"
pgrep -f "cloudflared.*tunnel.*run" >/dev/null && echo "OK tunnel"
pgrep -f "[g]ateway.*run" >/dev/null && echo "OK gateway"
pgrep -f "supervise[.]sh" >/dev/null && echo "OK supervise"

echo "--- Cron ---"
crontab -l | grep -c "hermuse-zerotrust" | xargs -I{} echo "OK cron ({} baris)"
```

Lalu buka `https://ai.domainkamu.my.id/login` di browser dan chat bot-mu di
Telegram. **Selesai!**

---

## Dua lapis pemantau

Kenapa ada dua? Karena menjaga dari dalam saja tidak cukup:

```
Lapisan 1 — supervise.sh (tiap 30 detik, dari DALAM)
  "Apakah proses 9Router / cloudflared / gateway masih hidup?"
  Mati -> nyalakan lagi. Binary hilang -> install ulang.

Lapisan 2 — monitor.sh via cron (tiap 10 menit, dari LUAR)
  "Apakah URL publik benar-benar bisa DIBUKA pengunjung?"
  Mati -> coba pulihkan -> kabari hanya kalau gangguan/pulih.
  + memastikan supervise.sh sendiri masih hidup (penjaga butuh penjaga)
  + menjalankan gateway-watch.sh (anti-stall bot Telegram)
```

Analogi: `supervise.sh` itu satpam yang keliling tiap 30 detik memastikan
pintu tidak jebol; `monitor.sh` itu pelanggan misterius yang tiap 10 menit
datang memastikan toko benar-benar buka.

---

## Perintah sehari-hari

```bash
# Lihat status semua komponen
bash scripts/monitor.sh && echo "---" && tail -5 monitor.log

# Restart manual per komponen
bash restart-9router.sh     # 9Router
bash restart-tunnel.sh      # tunnel cloudflared
bash start-gateway.sh       # Hermes Telegram gateway

# Lihat log
tail -f supervisor.log      # penjaga proses
tail -f 9router.log         # 9Router
tail -f cloudflared.log     # tunnel
tail -f gateway.log         # bot Telegram
tail -f monitor.log         # monitor cron

# Berhentikan semuanya (mis. sebelum maintenance)
pkill -f "supervise[.]sh"; pkill -f "/start-9router.sh"; pkill -f "cloudflared.*tunnel.*run"; pkill -f "[g]ateway.*run"
```

---

## Kalau ada masalah (troubleshooting)

| Gejala | Kemungkinan penyebab | Solusi |
|---|---|---|
| URL publik error **530** | `cloudflared` mati / token salah | `bash restart-tunnel.sh`, cek `cloudflared.log` |
| URL publik error **1033 / Argo Tunnel error** | Public Hostname belum ditambahkan di dashboard | Ulangi Langkah 3 bagian dashboard |
| `https://.../login` me-redirect | Normal — 9Router redirect ke halaman login | Bukan error, lanjutkan login |
| Bot Telegram tidak membalas, proses hidup | Stall polling | `gateway-watch.sh` otomatis restart tiap 5 mnt; cek `gateway-watch.log` |
| `hermes: command not found` di cron | PATH cron minimal | Script sudah mengatur PATH sendiri; kalau masih gagal, cek `which hermes` |
| Setelah reboot semua mati | cron `@reboot` belum kepasang | `bash scripts/install-cron.sh`, lalu `crontab -l` |
| `supervise.sh sudah jalan` tapi ragu | Lock aktif = memang sudah jalan | `pgrep -af "supervise[.]sh"` untuk memastikan |
| Token bocor / mau ganti tunnel | Token tersimpan di `~/.cloudflared-token` | Hapus file-nya, buat tunnel baru di dashboard, ulangi Langkah 3 |

---

## Keamanan

1. **Jangan pernah commit file rahasia.** Sudah diamankan `.gitignore`:
   `~/.cloudflared-token`, `.dashboard-pw`, `.tunnel-hostname`.
2. **Ganti password dashboard** (Langkah 4) — jangan pakai default.
3. **Allowlist Telegram**: `hermes gateway setup` hanya isi ID Telegram-mu —
   orang lain yang menemukan bot-mu tidak bisa memakainya.
4. (Opsional, lanjutan) Aktifkan **Cloudflare Access** di depan hostname
   untuk login tambahan sebelum dashboard terlihat.

---

## Layout file

```
Hermuse/
├── scripts/
│   ├── install.sh        # install otomatis: Node, Hermes, 9Router, cloudflared
│   ├── setup-tunnel.sh   # pasang Zero Trust Tunnel (token + hostname + tes)
│   ├── supervise.sh      # penjaga proses tiap 30 dtk (9Router+tunnel+gateway)
│   ├── monitor.sh        # health check URL publik tiap 10 mnt (via cron)
│   └── install-cron.sh   # pasang 3 cron: monitor, gateway-watch, supervise@reboot
├── run-hermes.sh         # jalankan Hermes CLI (ubah path venv di sini bila perlu)
├── start-9router.sh      # supervisor 9Router (loop + baca password dari file)
├── restart-9router.sh    # restart 9Router manual
├── restart-tunnel.sh     # restart cloudflared manual
├── start-gateway.sh      # nyalakan bot Telegram (detached)
├── gateway-watch.sh      # anti-stall: deteksi bot macet diam-diam
├── docs/
│   └── arsip-tunnel-gagal.md  # arsip: kenapa tunnel lama dipensiunkan
├── CHANGELOG.md
├── LICENSE               # MIT
└── README.md             # file ini
```

---

## Kredit

Fork modifikasi dari [imkofty/Hermuse](https://github.com/imkofty/Hermuse)
— lisensi tetap **MIT**, bebas dipakai dan diubah. Hermes Agent milik
[Nous Research](https://github.com/nousresearch/hermes-agent).
