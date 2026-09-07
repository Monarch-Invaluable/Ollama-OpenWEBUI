Tentu. Berikut `README.md` yang sesuai dengan script `setup-open-webui.sh` tersebut, termasuk arsitektur, fitur, instalasi, konfigurasi, troubleshooting, dan keamanan data.

<img width="1366" height="768" alt="image" src="https://github.com/user-attachments/assets/06045c58-eadd-47e7-8fdb-eb244dd8f07e" />


````markdown
# Ollama + Open WebUI — ThinkPad T430

Script otomatis untuk **install, repair, configure, dan health check** Ollama + Open WebUI menggunakan Docker.

Dirancang terutama untuk perangkat dengan resource terbatas seperti **ThinkPad T430**, tetapi dapat digunakan pada sistem Linux lainnya.

---

## 1. Arsitektur

```text
                         HOST LINUX
                    ┌─────────────────────┐
                    │                     │
                    │      Ollama         │
                    │                     │
                    │  0.0.0.0:11434      │
                    │         │           │
                    │         │           │
                    └─────────┼───────────┘
                              │
                              │ Docker Bridge
                              │
                    ┌─────────▼───────────┐
                    │                     │
                    │    Open WebUI       │
                    │      Docker         │
                    │                     │
                    │ host.docker.internal│
                    │       :11434        │
                    │                     │
                    │   Container :8080   │
                    └─────────┬───────────┘
                              │
                              │ Port Mapping
                              │
                         localhost:3000
                              │
                              ▼
                         Web Browser
````

### Komponen

| Komponen            | Konfigurasi                         |
| ------------------- | ----------------------------------- |
| Ollama              | `0.0.0.0:11434`                     |
| Ollama API          | `http://127.0.0.1:11434`            |
| Docker → Ollama     | `http://host.docker.internal:11434` |
| Open WebUI          | Docker                              |
| Open WebUI internal | `8080`                              |
| Open WebUI host     | `3000`                              |
| Docker volume       | `open-webui`                        |
| Default model       | `qwen2.5:1.5b`                      |

---

# 2. Fitur

Script `setup-open-webui.sh` melakukan pemeriksaan dan konfigurasi secara bertahap.

### System

* Mengecek `sudo`
* Mengecek RAM
* Mengecek disk
* Memberikan warning jika disk hampir penuh
* Tidak menjalankan cleanup destruktif secara otomatis

### Docker

* Mengecek Docker
* Memastikan Docker daemon aktif
* Mengaktifkan Docker saat boot
* Menampilkan versi Docker
* Menampilkan penggunaan storage Docker

### Network

* Mengecek DNS GHCR
* Mengecek DNS Docker Hub
* Mengecek koneksi registry
* Tidak memaksa pull jika image sudah tersedia lokal

### Ollama

* Mendeteksi binary Ollama
* Mengecek versi Ollama
* Membuat system user `ollama`
* Membuat system group `ollama`
* Membuat systemd service
* Mengkonfigurasi `OLLAMA_HOST`
* Mengaktifkan service saat boot
* Restart Ollama
* Memastikan API Ollama aktif
* Memeriksa port `11434`

### Model

Script memastikan model berikut tersedia:

```text
qwen2.5:1.5b
```

Jika model sudah ada:

```text
[OK] qwen2.5:1.5b sudah tersedia.
```

Model tidak akan di-download ulang.

### Open WebUI

* Menggunakan image:

```text
ghcr.io/open-webui/open-webui:main-slim
```

* Docker Hub fallback:

```text
openwebui/open-webui:main-slim
```

* Persistent volume
* Persistent secret key
* Docker restart policy
* Docker bridge configuration
* `host.docker.internal`
* Health check
* HTTP check
* Ollama connectivity check
* Model inference test

---

# 3. Persyaratan

Minimal:

* Linux
* Bash
* `sudo`
* Docker
* `curl`
* `systemd`
* Ollama
* Python atau curl di dalam container Open WebUI

Disarankan:

* RAM minimal 4 GB
* Storage kosong minimal 5 GB
* SSD lebih disarankan
* Docker Engine aktif

Untuk ThinkPad T430, model kecil lebih disarankan.

Contoh:

```text
qwen2.5:1.5b
llama3.2:1b
```

Model yang lebih besar akan membutuhkan RAM dan storage lebih banyak.

---

# 4. Struktur File

```text
.
├── setup-open-webui.sh
└── README.md
```

File utama:

```text
setup-open-webui.sh
```

adalah installer sekaligus repair dan diagnostic tool.

---

# 5. Instalasi

Clone atau buat file:

```bash
nano setup-open-webui.sh
```

Paste script ke dalam file tersebut.

Kemudian:

```bash
chmod +x setup-open-webui.sh
```

Jalankan:

```bash
./setup-open-webui.sh
```

Jika membutuhkan sudo:

```bash
sudo -v
./setup-open-webui.sh
```

---

# 6. Proses Script

Script memiliki 14 tahap utama.

```text
[1/14] CHECKING SYSTEM
[2/14] CHECKING DOCKER
[3/14] CHECKING NETWORK
[4/14] CHECKING OLLAMA
[5/14] CHECKING OLLAMA SERVICE
[6/14] CONFIGURING OLLAMA
[7/14] TESTING OLLAMA API
[8/14] CHECKING MODEL
[9/14] TESTING MODEL INFERENCE
[10/14] CHECKING PORTS
[11/14] CHECKING OPEN WEBUI VOLUME
[12/14] CHECKING OPEN WEBUI IMAGE
[13/14] STARTING OPEN WEBUI
[14/14] FULL OPEN WEBUI DIAGNOSTICS
```

---

# 7. Konfigurasi

Konfigurasi berada di bagian atas script.

```bash
APP_NAME="open-webui"

IMAGE_PRIMARY="ghcr.io/open-webui/open-webui:main-slim"
IMAGE_FALLBACK="openwebui/open-webui:main-slim"

WEBUI_PORT="3000"
WEBUI_INTERNAL_PORT="8080"

OLLAMA_HOST="0.0.0.0"
OLLAMA_PORT="11434"

OLLAMA_API="http://127.0.0.1:11434"
OLLAMA_CONTAINER_API="http://host.docker.internal:11434"

VOLUME_NAME="open-webui"

MODEL="qwen2.5:1.5b"
```

---

# 8. Mengganti Model

Untuk mengganti model default, ubah:

```bash
MODEL="qwen2.5:1.5b"
```

Contoh:

```bash
MODEL="llama3.2:1b"
```

atau:

```bash
MODEL="phi4-mini"
```

Pastikan model tersebut kompatibel dengan resource komputer.

Untuk ThinkPad T430 dengan RAM terbatas, model sekitar 1B–2B parameter lebih realistis.

---

# 9. Mengganti Port Open WebUI

Default:

```bash
WEBUI_PORT="3000"
```

Jika ingin menggunakan port `8080` pada host:

```bash
WEBUI_PORT="8080"
```

Internal container tetap:

```bash
WEBUI_INTERNAL_PORT="8080"
```

Sehingga:

```text
Host:
http://localhost:8080

Container:
:8080
```

---

# 10. Ollama

Ollama dikonfigurasi agar listen pada:

```text
0.0.0.0:11434
```

Konfigurasi utama:

```bash
OLLAMA_HOST="0.0.0.0"
OLLAMA_PORT="11434"
```

Systemd akan memiliki:

```ini
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

Drop-in juga dibuat:

```text
/etc/systemd/system/ollama.service.d/override.conf
```

Dengan:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

Hal ini membuat konfigurasi tetap eksplisit meskipun service Ollama dibuat atau diperbaiki oleh script.

---

# 11. Ollama Service

Service berada di:

```text
/etc/systemd/system/ollama.service
```

Perintah manual untuk melihatnya:

```bash
sudo systemctl cat ollama
```

Status:

```bash
sudo systemctl status ollama
```

Restart:

```bash
sudo systemctl restart ollama
```

Log:

```bash
sudo journalctl -u ollama -n 100 --no-pager
```

---

# 12. Ollama API

Test dari host:

```bash
curl http://127.0.0.1:11434/api/tags
```

Jika berhasil, akan mendapatkan JSON berisi model.

Contoh:

```json
{
  "models": []
}
```

atau daftar model yang sudah tersedia.

---

# 13. Docker → Ollama

Open WebUI berada di dalam Docker.

Oleh karena itu Open WebUI tidak menggunakan:

```text
127.0.0.1:11434
```

karena `127.0.0.1` dari dalam container menunjuk ke container itu sendiri.

Sebaliknya digunakan:

```text
host.docker.internal:11434
```

Konfigurasi:

```bash
OLLAMA_CONTAINER_API="http://host.docker.internal:11434"
```

Docker container dibuat dengan:

```bash
--add-host=host.docker.internal:host-gateway
```

Dan environment:

```bash
-e "OLLAMA_BASE_URL=http://host.docker.internal:11434"
```

---

# 14. Docker Network

Script memeriksa:

```text
docker0
```

dan mengambil:

* Docker gateway
* Docker subnet

Contoh:

```text
Gateway:
172.17.0.1

Subnet:
172.17.0.0/16
```

Dengan konfigurasi:

```text
Container
   │
   │
   ▼
172.17.0.1
   │
   ▼
Host
   │
   ▼
11434
   │
   ▼
Ollama
```

---

# 15. Firewall

Jika UFW aktif, script mencoba memastikan Docker bridge dapat mengakses Ollama.

Rule yang digunakan secara konsep:

```text
docker0
    ↓
Docker subnet
    ↓
TCP 11434
    ↓
Ollama
```

Script tidak melakukan konfigurasi firewall secara global.

Jika UFW tidak aktif, script tidak memaksakan perubahan.

---

# 16. Open WebUI Image

Primary image:

```text
ghcr.io/open-webui/open-webui:main-slim
```

Fallback:

```text
openwebui/open-webui:main-slim
```

Script terlebih dahulu mengecek image lokal.

Jika tersedia:

```text
[OK] Primary image tersedia secara lokal.
```

Maka tidak dilakukan pull.

Hal ini penting pada koneksi internet yang lambat atau registry yang tidak dapat diakses.

---

# 17. Persistent Volume

Volume:

```text
open-webui
```

digunakan untuk menyimpan data Open WebUI.

Mount:

```text
open-webui:/app/backend/data
```

Volume tidak dihapus oleh script.

Jangan menjalankan:

```bash
docker volume rm open-webui
```

jika ingin mempertahankan data Open WebUI.

---

# 18. Secret Key

Secret Open WebUI disimpan secara persistent di:

```text
~/.open-webui-secret
```

Permission:

```text
600
```

Secret tidak dibuat ulang setiap kali script dijalankan.

Hal ini membantu mempertahankan konfigurasi Open WebUI.

---

# 19. Menjalankan Open WebUI

Setelah script berhasil:

```bash
docker ps
```

Seharusnya terdapat:

```text
open-webui
```

Port:

```text
0.0.0.0:3000->8080/tcp
```

Akses melalui browser:

```text
http://localhost:3000
```

---

# 20. Pemeriksaan Manual

## Ollama

```bash
ollama --version
```

## Model

```bash
ollama list
```

## API

```bash
curl http://127.0.0.1:11434/api/tags
```

## Ollama service

```bash
sudo systemctl status ollama
```

## Docker

```bash
sudo docker ps
```

## Open WebUI log

```bash
sudo docker logs open-webui --tail 100
```

## Docker network

```bash
sudo docker network inspect bridge
```

## Port

```bash
sudo ss -lntp | grep -E '11434|3000'
```

---

# 21. Health Check

Script menggunakan beberapa indikator.

### Ollama

```text
OLLAMA : ONLINE
```

berarti:

* service aktif
* API merespons
* port tersedia

### Model

```text
MODEL : qwen2.5:1.5b AVAILABLE
```

berarti model tersedia secara lokal.

### Open WebUI

```text
OPEN WEBUI : CONTAINER RUNNING
```

berarti container berjalan.

### WebUI HTTP

```text
WEBUI HTTP : http://localhost:3000
```

berarti HTTP endpoint dapat diakses.

### Docker → Ollama

```text
WEBUI -> OLLAMA : CONNECTED
```

adalah pemeriksaan paling penting untuk memastikan Open WebUI dapat berbicara dengan Ollama.

### Container API

```text
CONTAINER API : CONNECTED
```

berarti endpoint:

```text
http://host.docker.internal:11434/api/tags
```

dapat diakses dari container.

### Container Model

```text
CONTAINER MODEL : WORKING
```

berarti Open WebUI container dapat meminta inference ke model Ollama.

---

# 22. Kondisi Sukses

Output ideal:

```text
======================================================
FINAL HEALTH REPORT
======================================================

[OK] OLLAMA           : ONLINE
[OK] MODEL            : qwen2.5:1.5b AVAILABLE
[OK] OPEN WEBUI       : CONTAINER RUNNING
[OK] WEBUI HTTP       : http://localhost:3000
[OK] WEBUI -> OLLAMA  : CONNECTED
[OK] CONTAINER API    : CONNECTED
[OK] CONTAINER MODEL  : WORKING

[OK] OLLAMA + OPEN WEBUI SIAP DIGUNAKAN.
```

Jika semua bagian tersebut hijau, sistem siap digunakan.

---

# 23. Troubleshooting

## A. Ollama API tidak aktif

Jalankan:

```bash
sudo systemctl status ollama
```

Kemudian:

```bash
sudo journalctl -u ollama -n 100 --no-pager
```

Periksa:

```bash
sudo ss -lntp | grep 11434
```

Target:

```text
0.0.0.0:11434
```

---

## B. Ollama hanya listen di 127.0.0.1

Periksa:

```bash
sudo systemctl cat ollama
```

Harus terdapat:

```ini
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

Kemudian:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Periksa kembali:

```bash
sudo ss -lntp | grep 11434
```

---

## C. `host.docker.internal` tidak ditemukan

Periksa:

```bash
sudo docker exec open-webui \
    getent hosts host.docker.internal
```

Seharusnya menghasilkan alamat seperti:

```text
172.17.0.1 host.docker.internal
```

Container harus dibuat menggunakan:

```bash
--add-host=host.docker.internal:host-gateway
```

---

## D. Docker tidak dapat mengakses Ollama

Test:

```bash
sudo docker exec open-webui \
    curl -v \
    http://host.docker.internal:11434/api/tags
```

Jika gagal, periksa:

```bash
sudo ss -lntp | grep 11434
```

Kemudian:

```bash
sudo ufw status
```

Jika UFW aktif, periksa rule Docker:

```bash
sudo ufw status numbered
```

---

## E. Open WebUI berjalan tetapi tidak melihat model

Periksa environment container:

```bash
sudo docker inspect open-webui \
    -f '{{range .Config.Env}}{{println .}}{{end}}' |
    grep OLLAMA_BASE_URL
```

Target:

```text
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

Kemudian test:

```bash
sudo docker exec open-webui \
    curl \
    http://host.docker.internal:11434/api/tags
```

---

## F. Open WebUI tidak dapat dibuka

Periksa:

```bash
sudo docker ps
```

Kemudian:

```bash
sudo docker logs open-webui --tail 200
```

Periksa port:

```bash
sudo ss -lntp | grep 3000
```

Test:

```bash
curl -I http://127.0.0.1:3000
```

---

# 24. Disk Penuh

ThinkPad T430 dengan storage kecil perlu diperhatikan.

Periksa:

```bash
df -h /
```

Periksa Docker:

```bash
sudo docker system df
```

Periksa direktori home:

```bash
du -xh ~ --max-depth=1 2>/dev/null | sort -h
```

Periksa `/var`:

```bash
sudo du -xh /var --max-depth=1 2>/dev/null | sort -h
```

Script sengaja **tidak menjalankan**:

```bash
docker system prune -a
```

secara otomatis.

Ini dilakukan untuk mencegah image/model/data terhapus tanpa konfirmasi.

---

# 25. Model Ollama

Lihat model:

```bash
ollama list
```

Download model secara manual:

```bash
ollama pull qwen2.5:1.5b
```

Hapus model jika benar-benar diperlukan:

```bash
ollama rm nama-model
```

Jangan menghapus model hanya untuk memperbaiki koneksi Open WebUI.

Masalah:

```text
Docker -> Ollama
```

berbeda dengan:

```text
Model -> Ollama
```

---

# 26. Restart Semua Komponen

Restart Docker:

```bash
sudo systemctl restart docker
```

Restart Ollama:

```bash
sudo systemctl restart ollama
```

Restart Open WebUI:

```bash
sudo docker restart open-webui
```

Atau jalankan kembali:

```bash
./setup-open-webui.sh
```

Script dirancang sebagai **repair / health-check script**, sehingga dapat dijalankan kembali.

---

# 27. Backup Open WebUI

Sebelum melakukan perubahan besar, backup volume:

```bash
sudo docker run --rm \
    -v open-webui:/data \
    -v "$PWD:/backup" \
    alpine \
    tar czf /backup/open-webui-backup.tar.gz \
    -C /data .
```

File backup:

```text
open-webui-backup.tar.gz
```

---

# 28. Restore Open WebUI

Jika diperlukan restore:

```bash
sudo docker run --rm \
    -v open-webui:/data \
    -v "$PWD:/backup" \
    alpine \
    sh -c 'rm -rf /data/* && tar xzf /backup/open-webui-backup.tar.gz -C /data'
```

**Pastikan backup benar sebelum menjalankan restore.**

---

# 29. Keamanan

Open WebUI dipublish pada:

```text
0.0.0.0:3000
```

Ini berarti port host dapat listen pada seluruh interface jaringan.

Untuk penggunaan lokal saja, lebih aman menggunakan binding:

```bash
-p 127.0.0.1:3000:8080
```

Dengan demikian WebUI hanya dapat diakses dari komputer itu sendiri.

Jika membutuhkan akses dari perangkat lain di LAN, gunakan firewall dan autentikasi dengan benar.

Jangan membuka port:

```text
11434
```

ke internet tanpa alasan dan konfigurasi keamanan yang tepat.

---

# 30. Kenapa Menggunakan `main-slim`

Image:

```text
ghcr.io/open-webui/open-webui:main-slim
```

dipilih untuk mengurangi ukuran image dibanding varian yang lebih besar.

Ini berguna pada perangkat dengan:

* storage terbatas
* bandwidth terbatas
* RAM terbatas
* CPU lama

Seperti ThinkPad T430.

---

# 31. Filosofi Script

Script ini sengaja menggunakan prinsip:

```text
CHECK
  ↓
VERIFY
  ↓
CONFIGURE
  ↓
TEST
  ↓
REPAIR
  ↓
VERIFY AGAIN
```

Bukan sekadar:

```text
INSTALL
  ↓
ASSUME WORKING
```

Karena instalasi berhasil belum tentu berarti:

```text
Open WebUI
      ↓
Docker Network
      ↓
Host
      ↓
Ollama
      ↓
Model
```

benar-benar terhubung.

---

# 32. Data yang Dipertahankan

Script tidak sengaja menghapus:

```text
Ollama models
```

```text
Docker volume open-webui
```

```text
~/.open-webui-secret
```

Script juga tidak menjalankan:

```bash
docker system prune -a
```

atau:

```bash
docker volume prune
```

secara otomatis.

---

# 33. Data yang Dapat Berubah

Script dapat mengubah:

```text
/etc/systemd/system/ollama.service
```

```text
/etc/systemd/system/ollama.service.d/override.conf
```

Docker container:

```text
open-webui
```

Firewall UFW jika UFW aktif dan rule Ollama diperlukan.

Perubahan tersebut dilakukan untuk memastikan koneksi:

```text
Open WebUI → Docker → Host → Ollama
```

---

# 34. Perintah Cepat

### Start

```bash
./setup-open-webui.sh
```

### Open WebUI

```text
http://localhost:3000
```

### Ollama API

```text
http://127.0.0.1:11434
```

### Model

```bash
ollama list
```

### Container

```bash
sudo docker ps
```

### WebUI log

```bash
sudo docker logs open-webui -f
```

### Ollama log

```bash
sudo journalctl -u ollama -f
```

### Port

```bash
sudo ss -lntp | grep -E '3000|11434'
```

### Docker network

```bash
sudo docker network inspect bridge
```

---

# 35. Expected Final Architecture

```text
                         ┌───────────────────────┐
                         │       Browser         │
                         │                       │
                         │ http://localhost:3000 │
                         └───────────┬───────────┘
                                     │
                                     ▼
                         ┌───────────────────────┐
                         │     Docker Host       │
                         │                       │
                         │       :3000           │
                         └───────────┬───────────┘
                                     │
                              port mapping
                                     │
                                     ▼
                  ┌────────────────────────────────┐
                  │          open-webui             │
                  │                                │
                  │        Docker Container        │
                  │             :8080              │
                  │                                │
                  │ OLLAMA_BASE_URL=               │
                  │ http://host.docker.internal:   │
                  │ 11434                           │
                  └───────────────┬────────────────┘
                                  │
                            Docker bridge
                                  │
                                  ▼
                         host.docker.internal
                                  │
                                  ▼
                         ┌──────────────────┐
                         │      Ollama      │
                         │                  │
                         │   0.0.0.0:11434  │
                         └────────┬─────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │      Models      │
                         │                  │
                         │ qwen2.5:1.5b     │
                         │ llama3.2:1b      │
                         │ phi4-mini        │
                         │ gemma3:4b        │
                         └──────────────────┘
```

---

# 36. Status Akhir

Jika konfigurasi berhasil, sistem memiliki rantai koneksi:

```text
Browser
   │
   ▼
Open WebUI :3000
   │
   ▼
Docker :8080
   │
   ▼
host.docker.internal
   │
   ▼
Ollama :11434
   │
   ▼
qwen2.5:1.5b
```

Dengan demikian Open WebUI bukan hanya **berjalan**, tetapi juga sudah dapat melakukan:

```text
HTTP
  ↓
Docker Network
  ↓
Ollama API
  ↓
Model Discovery
  ↓
Model Inference
```

---

## License

Gunakan dan modifikasi script ini sesuai kebutuhan.

Tidak ada jaminan bahwa konfigurasi akan cocok untuk seluruh distribusi Linux, versi Docker, versi Ollama, atau konfigurasi firewall.

Selalu backup data penting sebelum melakukan perubahan sistem.

```
```
