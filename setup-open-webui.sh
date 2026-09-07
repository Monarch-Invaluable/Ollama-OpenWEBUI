#!/bin/bash

set -Eeuo pipefail

# ============================================================
# THINKPAD T430
# OLLAMA + OPEN WEBUI
# INSTALL / REPAIR / HEALTH CHECK
#
# Target:
#   Ollama  -> 0.0.0.0:11434
#   OpenWebUI -> localhost:3000
#   Docker -> host.docker.internal:11434
#
# IMPORTANT:
#   - Tidak menghapus model Ollama
#   - Tidak menghapus volume Open WebUI
#   - Tidak melakukan docker system prune otomatis
#   - Tidak pull image jika image sudah tersedia lokal
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

APP_NAME="open-webui"

IMAGE_PRIMARY="ghcr.io/open-webui/open-webui:main-slim"
IMAGE_FALLBACK="openwebui/open-webui:main-slim"

IMAGE=""

WEBUI_PORT="3000"
WEBUI_INTERNAL_PORT="8080"

OLLAMA_HOST="0.0.0.0"
OLLAMA_PORT="11434"

OLLAMA_API="http://127.0.0.1:${OLLAMA_PORT}"
OLLAMA_CONTAINER_API="http://host.docker.internal:${OLLAMA_PORT}"

VOLUME_NAME="open-webui"

MODEL="qwen2.5:1.5b"

DOCKER="sudo docker"

OLLAMA_SERVICE_FILE="/etc/systemd/system/ollama.service"
OLLAMA_DROPIN_DIR="/etc/systemd/system/ollama.service.d"
OLLAMA_OVERRIDE="${OLLAMA_DROPIN_DIR}/override.conf"

DOCKER_PULL_TIMEOUT="900"
OLLAMA_TIMEOUT="60"
WEBUI_TIMEOUT="120"
MODEL_TIMEOUT="120"

# Jangan download jika disk di bawah angka ini.
MIN_FREE_GB="2"

# Model download membutuhkan ruang lebih besar.
MODEL_MIN_FREE_GB="4"

# Image pull membutuhkan ruang lebih besar.
IMAGE_MIN_FREE_GB="3"

SECRET_FILE="${HOME}/.open-webui-secret"


# ============================================================
# COLORS
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
# FUNCTIONS
# ============================================================

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

separator() {
    echo ""
    echo "======================================================"
    echo "$1"
    echo "======================================================"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

free_disk_gb() {
    local avail_kb

    avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')

    echo $((avail_kb / 1024 / 1024))
}

container_exists() {
    $DOCKER container inspect "$1" >/dev/null 2>&1
}

container_running() {
    if ! container_exists "$1"; then
        return 1
    fi

    [[ "$(
        $DOCKER inspect \
            -f '{{.State.Running}}' \
            "$1" \
            2>/dev/null ||
            echo false
    )" == "true" ]]
}

image_exists() {
    $DOCKER image inspect "$1" >/dev/null 2>&1
}


# ============================================================
# ERROR HANDLER
# ============================================================

trap '
    rc=$?
    if [ "$rc" -ne 0 ]; then
        error "Script berhenti."
        error "Line    : $LINENO"
        error "Command : ${BASH_COMMAND}"
        error "Exit    : $rc"
    fi
' ERR


# ============================================================
# HEADER
# ============================================================

clear || true

echo "======================================================"
echo "     THINKPAD T430 - OLLAMA + OPEN WEBUI"
echo "======================================================"
echo ""
echo "Model       : ${MODEL}"
echo "WebUI       : http://localhost:${WEBUI_PORT}"
echo "Ollama      : ${OLLAMA_API}"
echo "Volume      : ${VOLUME_NAME}"
echo ""
echo "======================================================"


# ============================================================
# 1. SYSTEM
# ============================================================

separator "[1/14] CHECKING SYSTEM"

if ! command_exists sudo; then
    die "sudo tidak ditemukan."
fi

if ! sudo -n true 2>/dev/null; then
    info "Memerlukan password sudo..."
    sudo -v
fi

ok "Sudo tersedia."

echo ""
echo "Memory:"
free -h

echo ""
echo "Disk:"
df -h /

ROOT_AVAIL_GB=$(free_disk_gb)

echo ""

if (( ROOT_AVAIL_GB < MIN_FREE_GB )); then

    error "Disk root terlalu penuh."
    echo ""
    echo "Free space : ${ROOT_AVAIL_GB} GB"
    echo "Minimum    : ${MIN_FREE_GB} GB"
    echo ""
    echo "Docker/Ollama download tidak aman."
    echo ""
    echo "Periksa:"
    echo "  sudo docker system df"
    echo "  du -xh ~ --max-depth=1 2>/dev/null | sort -h"
    echo "  sudo du -xh /var --max-depth=1 2>/dev/null | sort -h"

    exit 1

elif (( ROOT_AVAIL_GB < 10 )); then

    warn "Disk root tinggal ${ROOT_AVAIL_GB} GB."
    warn "Hindari download image/model besar yang tidak diperlukan."

else

    ok "Free disk: ${ROOT_AVAIL_GB} GB."

fi


# ============================================================
# 2. DOCKER
# ============================================================

separator "[2/14] CHECKING DOCKER"

if ! command_exists docker; then
    die "Docker belum terinstall."
fi

sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker

if ! sudo systemctl is-active --quiet docker; then
    die "Docker daemon tidak berjalan."
fi

if ! $DOCKER info >/dev/null 2>&1; then
    die "Docker CLI tidak dapat berkomunikasi dengan daemon."
fi

ok "Docker aktif."

echo ""

$DOCKER version --format \
    'Client: {{.Client.Version}} | Server: {{.Server.Version}}' \
    2>/dev/null ||
    true

echo ""

info "Docker disk usage:"

$DOCKER system df 2>/dev/null || true


# ============================================================
# 3. NETWORK / REGISTRY
# ============================================================

separator "[3/14] CHECKING NETWORK"

if command_exists getent; then

    if getent hosts ghcr.io >/dev/null 2>&1; then
        ok "DNS ghcr.io dapat di-resolve."
    else
        warn "DNS ghcr.io gagal."
    fi

    if getent hosts registry-1.docker.io >/dev/null 2>&1; then
        ok "DNS Docker Hub dapat di-resolve."
    else
        warn "DNS Docker Hub gagal."
    fi

fi


# ------------------------------------------------------------
# Registry access
# ------------------------------------------------------------

GHCR_OK=0
DOCKERHUB_OK=0

if command_exists curl; then

    if curl -fsSL \
        --connect-timeout 10 \
        --max-time 20 \
        https://ghcr.io/v2/ \
        >/dev/null 2>&1
    then

        GHCR_OK=1
        ok "GHCR dapat diakses."

    else

        warn "GHCR tidak dapat diakses."

    fi


    if curl -fsSL \
        --connect-timeout 10 \
        --max-time 20 \
        https://registry-1.docker.io/v2/ \
        >/dev/null 2>&1
    then

        DOCKERHUB_OK=1
        ok "Docker Hub dapat diakses."

    else

        warn "Docker Hub tidak dapat diakses."

    fi

else

    warn "curl tidak ditemukan. Registry check dilewati."

fi


# ============================================================
# 4. OLLAMA INSTALL CHECK
# ============================================================

separator "[4/14] CHECKING OLLAMA"

if ! command_exists ollama; then
    die "Ollama belum terinstall."
fi

OLLAMA_BIN=$(command -v ollama)

OLLAMA_VERSION=$(
    ollama --version 2>/dev/null ||
    true
)

if [ -n "${OLLAMA_VERSION}" ]; then
    ok "Ollama ditemukan: ${OLLAMA_VERSION}"
else
    warn "Versi Ollama tidak dapat dibaca."
fi

echo ""
echo "Ollama binary:"
echo "  ${OLLAMA_BIN}"


# ============================================================
# 5. OLLAMA SERVICE
# ============================================================

separator "[5/14] CHECKING OLLAMA SERVICE"


# ------------------------------------------------------------
# Create group
# ------------------------------------------------------------

if ! getent group ollama >/dev/null 2>&1; then

    info "Membuat system group ollama..."

    sudo groupadd \
        --system \
        ollama

    ok "Group ollama dibuat."

else

    ok "Group ollama tersedia."

fi


# ------------------------------------------------------------
# Create user
# ------------------------------------------------------------

if ! id ollama >/dev/null 2>&1; then

    info "Membuat system user ollama..."

    sudo useradd \
        --system \
        --gid ollama \
        --home-dir /usr/share/ollama \
        --create-home \
        --shell /usr/sbin/nologin \
        ollama

    ok "User ollama dibuat."

else

    ok "User ollama tersedia."

fi


# ------------------------------------------------------------
# Ollama directory
# ------------------------------------------------------------

sudo mkdir -p /usr/share/ollama

sudo chown -R \
    ollama:ollama \
    /usr/share/ollama

sudo chmod 755 \
    /usr/share/ollama


# ------------------------------------------------------------
# Create service
# ------------------------------------------------------------

if [ ! -f "${OLLAMA_SERVICE_FILE}" ]; then

    warn "ollama.service tidak ditemukan."
    info "Membuat systemd service Ollama..."

fi


sudo tee "${OLLAMA_SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

ExecStart=${OLLAMA_BIN} serve

User=ollama
Group=ollama

Restart=always
RestartSec=3

Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=${OLLAMA_HOST}:${OLLAMA_PORT}"

[Install]
WantedBy=multi-user.target
EOF

ok "ollama.service tersedia."


# ============================================================
# 6. CONFIGURE OLLAMA
# ============================================================

separator "[6/14] CONFIGURING OLLAMA"


# ------------------------------------------------------------
# Drop-in
# ------------------------------------------------------------

sudo mkdir -p \
    "${OLLAMA_DROPIN_DIR}"


sudo tee "${OLLAMA_OVERRIDE}" >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST}:${OLLAMA_PORT}"
EOF

ok "Ollama override dibuat."


echo ""
echo "Configuration:"
echo "  OLLAMA_HOST=${OLLAMA_HOST}:${OLLAMA_PORT}"


# ------------------------------------------------------------
# Reload systemd
# ------------------------------------------------------------

sudo systemctl daemon-reload


# ------------------------------------------------------------
# Enable
# ------------------------------------------------------------

sudo systemctl enable ollama >/dev/null 2>&1

ok "ollama.service enabled."


# ------------------------------------------------------------
# Restart
# ------------------------------------------------------------

info "Restarting Ollama..."

sudo systemctl restart ollama

sleep 3


# ------------------------------------------------------------
# Service status
# ------------------------------------------------------------

if sudo systemctl is-active --quiet ollama; then

    ok "ollama.service aktif."

else

    error "ollama.service gagal aktif."

    echo ""
    sudo systemctl status \
        ollama \
        --no-pager \
        -l ||
        true

    echo ""
    echo "Ollama journal:"

    sudo journalctl \
        -u ollama \
        -n 100 \
        --no-pager ||
        true

    exit 1

fi


# ------------------------------------------------------------
# Verify unit
# ------------------------------------------------------------

UNIT_FILE_STATE=$(
    sudo systemctl show \
        ollama \
        --property=UnitFileState \
        --value \
        2>/dev/null ||
        true
)

if [[ "${UNIT_FILE_STATE}" == "enabled" ]]; then
    ok "ollama.service enabled."
else
    warn "Status enable: ${UNIT_FILE_STATE:-unknown}"
fi


# ------------------------------------------------------------
# Verify DropIn
# ------------------------------------------------------------

DROPINS=$(
    sudo systemctl show \
        ollama \
        --property=DropInPaths \
        --no-pager \
        2>/dev/null ||
        true
)

if echo "${DROPINS}" |
    grep -q "override.conf"
then

    ok "Systemd override terdeteksi."

else

    warn "Drop-in override tidak terdeteksi."

fi


# ------------------------------------------------------------
# Verify effective systemd environment
# ------------------------------------------------------------

SYSTEMD_ENV=$(
    sudo systemctl show \
        ollama \
        --property=Environment \
        --no-pager \
        2>/dev/null ||
        true
)

if echo "${SYSTEMD_ENV}" |
    grep -qF \
    "OLLAMA_HOST=${OLLAMA_HOST}:${OLLAMA_PORT}"
then

    ok "OLLAMA_HOST aktif pada systemd."

else

    error "OLLAMA_HOST tidak terlihat pada systemd."

    echo ""
    echo "systemctl show:"
    echo "${SYSTEMD_ENV}"

    echo ""
    echo "Service:"
    sudo systemctl cat ollama \
        --no-pager ||
        true

    exit 1

fi


# ------------------------------------------------------------
# Process PID
# ------------------------------------------------------------

OLLAMA_PID=$(
    pgrep -xo ollama ||
    true
)

if [ -n "${OLLAMA_PID}" ]; then

    ok "Ollama process ditemukan: PID ${OLLAMA_PID}"

else

    warn "PID Ollama belum ditemukan."

fi


# ============================================================
# 7. OLLAMA API TEST
# ============================================================

separator "[7/14] TESTING OLLAMA API"

OLLAMA_READY=0

info "Menunggu Ollama API..."

for i in $(seq 1 "${OLLAMA_TIMEOUT}"); do

    if curl -fsS \
        --connect-timeout 2 \
        --max-time 5 \
        "${OLLAMA_API}/api/tags" \
        >/dev/null 2>&1
    then

        OLLAMA_READY=1
        break

    fi

    sleep 1

done


if [ "${OLLAMA_READY}" -ne 1 ]; then

    error "Ollama API tidak merespons."

    echo ""
    sudo systemctl status \
        ollama \
        --no-pager \
        -l ||
        true

    echo ""
    sudo journalctl \
        -u ollama \
        -n 100 \
        --no-pager ||
        true

    exit 1

fi

ok "Ollama API aktif."


# ------------------------------------------------------------
# Port check
# ------------------------------------------------------------

echo ""

LISTEN_INFO=$(
    sudo ss -lntp 2>/dev/null |
    grep ":${OLLAMA_PORT} " ||
    true
)

if echo "${LISTEN_INFO}" |
    grep -qE \
    "0\.0\.0\.0:${OLLAMA_PORT}|\[::\]:${OLLAMA_PORT}"
then

    ok "Ollama listen pada 0.0.0.0:${OLLAMA_PORT}"

elif echo "${LISTEN_INFO}" |
    grep -q "127.0.0.1:${OLLAMA_PORT}"
then

    error "Ollama hanya listen pada 127.0.0.1."

    echo "${LISTEN_INFO}"

    die "Docker tidak akan dapat mengakses Ollama."

else

    warn "Port Ollama tidak dapat diverifikasi."

    echo "${LISTEN_INFO}"

fi


# ============================================================
# DOCKER BRIDGE FIREWALL PREPARATION
# ============================================================

echo ""
info "Checking Docker bridge..."

DOCKER_BRIDGE_IF="docker0"

if ip link show "${DOCKER_BRIDGE_IF}" \
    >/dev/null 2>&1
then

    ok "Interface ${DOCKER_BRIDGE_IF} tersedia."

else

    warn "Interface ${DOCKER_BRIDGE_IF} tidak ditemukan."

fi


# ------------------------------------------------------------
# Docker gateway
# ------------------------------------------------------------

DOCKER_GATEWAY=$(
    $DOCKER network inspect bridge \
        -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' \
        2>/dev/null ||
        true
)

if [ -n "${DOCKER_GATEWAY}" ]; then

    ok "Docker bridge gateway: ${DOCKER_GATEWAY}"

else

    warn "Gateway Docker bridge tidak ditemukan."

fi


# ------------------------------------------------------------
# Docker subnet
# ------------------------------------------------------------

DOCKER_SUBNET=$(
    $DOCKER network inspect bridge \
        -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' \
        2>/dev/null ||
        true
)

if [ -n "${DOCKER_SUBNET}" ]; then

    info "Docker bridge subnet: ${DOCKER_SUBNET}"

else

    warn "Docker bridge subnet tidak ditemukan."

fi


# ============================================================
# FIREWALL
# ============================================================

info "Checking firewall..."

UFW_ACTIVE=0

if command_exists ufw; then

    UFW_STATUS=$(
        sudo ufw status 2>/dev/null |
        head -n 1 ||
        true
    )

    if echo "${UFW_STATUS}" |
        grep -qi "active"
    then

        UFW_ACTIVE=1

        ok "UFW aktif."

    else

        info "UFW tidak aktif."

    fi

else

    info "UFW tidak terinstall."

fi


# ------------------------------------------------------------
# UFW Docker -> Ollama
# ------------------------------------------------------------

if [ "${UFW_ACTIVE}" -eq 1 ] &&
   [ -n "${DOCKER_SUBNET}" ]
then

    info "Memastikan Docker bridge dapat mengakses Ollama..."

    if sudo ufw allow in on "${DOCKER_BRIDGE_IF}" \
        from "${DOCKER_SUBNET}" \
        to any port "${OLLAMA_PORT}" \
        proto tcp \
        >/dev/null 2>&1
    then

        ok "UFW rule Docker -> Ollama tersedia."

    else

        warn "Tidak dapat membuat UFW rule Docker -> Ollama."

    fi

fi


# ------------------------------------------------------------
# iptables informational check
# ------------------------------------------------------------

if command_exists iptables; then

    IPTABLES_OLLAMA=$(
        sudo iptables -S 2>/dev/null |
        grep -E \
        "11434|DOCKER-USER" ||
        true
    )

    if [ -n "${IPTABLES_OLLAMA}" ]; then

        debug "iptables memiliki rule terkait Docker/Ollama."

    else

        info "Tidak ada iptables rule khusus port 11434."

    fi

fi


# ============================================================
# 8. OLLAMA MODEL
# ============================================================

separator "[8/14] CHECKING MODEL"

echo ""
echo "Installed models:"

ollama list

if ollama list |
    awk 'NR>1 {print $1}' |
    grep -Fxq "${MODEL}"
then

    ok "${MODEL} sudah tersedia."

else

    info "${MODEL} belum tersedia."

    ROOT_AVAIL_GB=$(free_disk_gb)

    if (( ROOT_AVAIL_GB < MODEL_MIN_FREE_GB )); then

        error "Ruang disk terlalu kecil untuk download model."

        echo ""
        echo "Free : ${ROOT_AVAIL_GB} GB"
        echo "Need : minimal ${MODEL_MIN_FREE_GB} GB"

        exit 1

    fi

    info "Downloading ${MODEL}..."

    if ollama pull "${MODEL}"; then

        ok "${MODEL} berhasil di-download."

    else

        die "Gagal download model ${MODEL}."

    fi

fi


# ============================================================
# 9. MODEL TEST
# ============================================================

separator "[9/14] TESTING MODEL INFERENCE"

info "Testing ${MODEL}..."

MODEL_RESPONSE=$(
    timeout "${MODEL_TIMEOUT}" \
        ollama run "${MODEL}" \
        "Reply with exactly: OLLAMA_OK" \
        2>/dev/null ||
        true
)

if [ -n "${MODEL_RESPONSE}" ]; then

    if echo "${MODEL_RESPONSE}" |
        grep -qi "OLLAMA_OK"
    then

        ok "Model inference berhasil."

    else

        warn "Model memberikan respons berbeda."

        echo ""
        echo "${MODEL_RESPONSE}" |
            head -c 1000

        echo ""

        ok "Model tetap memberikan respons."

    fi

else

    die "Model tidak memberikan respons."

fi


# ============================================================
# 10. PORT CHECK
# ============================================================

separator "[10/14] CHECKING PORTS"


# ------------------------------------------------------------
# Ollama
# ------------------------------------------------------------

if sudo ss -lntp 2>/dev/null |
    grep -q ":${OLLAMA_PORT} "
then

    ok "Port Ollama ${OLLAMA_PORT} aktif."

else

    error "Port Ollama ${OLLAMA_PORT} tidak aktif."

fi


# ------------------------------------------------------------
# WebUI
# ------------------------------------------------------------

if sudo ss -lntp 2>/dev/null |
    grep -q ":${WEBUI_PORT} "
then

    warn "Port ${WEBUI_PORT} sedang digunakan."

    if $DOCKER ps \
        --format '{{.Names}}' |
        grep -Fxq "${APP_NAME}"
    then

        ok "Port digunakan oleh Open WebUI."

    else

        die "Port ${WEBUI_PORT} digunakan aplikasi lain."

    fi

else

    ok "Port ${WEBUI_PORT} tersedia."

fi


# ============================================================
# 11. VOLUME
# ============================================================

separator "[11/14] CHECKING OPEN WEBUI VOLUME"

if $DOCKER volume inspect \
    "${VOLUME_NAME}" \
    >/dev/null 2>&1
then

    ok "Volume ${VOLUME_NAME} sudah ada."
    info "Data Open WebUI dipertahankan."

else

    info "Membuat volume ${VOLUME_NAME}..."

    $DOCKER volume create \
        "${VOLUME_NAME}" \
        >/dev/null

    ok "Volume dibuat."

fi


# ============================================================
# 12. OPEN WEBUI IMAGE
# ============================================================

separator "[12/14] CHECKING OPEN WEBUI IMAGE"

info "Primary:"
echo "  ${IMAGE_PRIMARY}"

info "Fallback:"
echo "  ${IMAGE_FALLBACK}"

IMAGE_AVAILABLE=0


# ------------------------------------------------------------
# Local primary
# ------------------------------------------------------------

if image_exists "${IMAGE_PRIMARY}"; then

    IMAGE="${IMAGE_PRIMARY}"
    IMAGE_AVAILABLE=1

    ok "Primary image tersedia secara lokal."

fi


# ------------------------------------------------------------
# Local fallback
# ------------------------------------------------------------

if [ "${IMAGE_AVAILABLE}" -eq 0 ] &&
   image_exists "${IMAGE_FALLBACK}"
then

    IMAGE="${IMAGE_FALLBACK}"
    IMAGE_AVAILABLE=1

    ok "Fallback image tersedia secara lokal."

fi


# ------------------------------------------------------------
# Pull
# ------------------------------------------------------------

if [ "${IMAGE_AVAILABLE}" -eq 0 ]; then

    ROOT_AVAIL_GB=$(free_disk_gb)

    if (( ROOT_AVAIL_GB < IMAGE_MIN_FREE_GB )); then

        error "Disk terlalu penuh untuk Docker image."

        echo ""
        echo "Free : ${ROOT_AVAIL_GB} GB"
        echo "Need : minimal ${IMAGE_MIN_FREE_GB} GB"

        echo ""
        $DOCKER system df || true

        exit 1

    fi


    # --------------------------------------------------------
    # GHCR
    # --------------------------------------------------------

    if [ "${GHCR_OK}" -eq 1 ]; then

        info "Pulling Open WebUI dari GHCR..."

        if timeout "${DOCKER_PULL_TIMEOUT}" \
            $DOCKER pull "${IMAGE_PRIMARY}"
        then

            IMAGE="${IMAGE_PRIMARY}"
            IMAGE_AVAILABLE=1

            ok "Open WebUI image berhasil dari GHCR."

        else

            warn "GHCR pull gagal."

        fi

    else

        warn "GHCR tidak dapat diakses."

    fi


    # --------------------------------------------------------
    # Docker Hub
    # --------------------------------------------------------

    if [ "${IMAGE_AVAILABLE}" -eq 0 ] &&
       [ "${DOCKERHUB_OK}" -eq 1 ]
    then

        info "Pulling Open WebUI dari Docker Hub..."

        if timeout "${DOCKER_PULL_TIMEOUT}" \
            $DOCKER pull "${IMAGE_FALLBACK}"
        then

            IMAGE="${IMAGE_FALLBACK}"
            IMAGE_AVAILABLE=1

            ok "Open WebUI image berhasil dari Docker Hub."

        else

            warn "Docker Hub pull gagal."

        fi

    fi

fi


# ------------------------------------------------------------
# Image failure
# ------------------------------------------------------------

if [ "${IMAGE_AVAILABLE}" -eq 0 ]; then

    error "Image Open WebUI tidak tersedia."

    echo ""
    echo "Kemungkinan:"
    echo "  - Registry tidak dapat diakses"
    echo "  - Image belum pernah di-download"
    echo "  - Disk terlalu penuh"

    echo ""
    echo "Docker images:"

    $DOCKER images \
        --format \
        'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'

    echo ""
    echo "Docker disk:"

    $DOCKER system df ||
        true

    echo ""
    echo "Container lama TIDAK dihapus."
    echo "Volume ${VOLUME_NAME} TIDAK dihapus."

    exit 1

fi


# ============================================================
# 13. START OPEN WEBUI
# ============================================================

separator "[13/14] STARTING OPEN WEBUI"


# ------------------------------------------------------------
# Secret
# ------------------------------------------------------------

if [ -f "${SECRET_FILE}" ] &&
   [ -s "${SECRET_FILE}" ]
then

    WEBUI_SECRET_KEY=$(
        cat "${SECRET_FILE}"
    )

else

    if command_exists openssl; then

        WEBUI_SECRET_KEY=$(
            openssl rand -hex 32
        )

    else

        WEBUI_SECRET_KEY=$(
            head -c 128 /dev/urandom |
            base64 |
            tr -dc 'A-Za-z0-9' |
            head -c 64
        )

    fi

    printf '%s\n' \
        "${WEBUI_SECRET_KEY}" \
        > "${SECRET_FILE}"

    chmod 600 \
        "${SECRET_FILE}"

fi

ok "Persistent WebUI secret tersedia."


# ------------------------------------------------------------
# Verify port isn't occupied by foreign process
# ------------------------------------------------------------

PORT_OWNER=$(
    sudo ss -lntp 2>/dev/null |
    grep ":${WEBUI_PORT} " ||
    true
)

if [ -n "${PORT_OWNER}" ]; then

    if ! $DOCKER ps \
        --format '{{.Names}}' |
        grep -Fxq "${APP_NAME}"
    then

        error "Port ${WEBUI_PORT} sudah digunakan aplikasi lain."

        echo "${PORT_OWNER}"

        exit 1

    fi

fi


# ------------------------------------------------------------
# Existing container
# ------------------------------------------------------------

OLD_CONTAINER_EXISTS=0

if container_exists "${APP_NAME}"; then

    OLD_CONTAINER_EXISTS=1

    info "Container lama ditemukan."

    # --------------------------------------------------------
    # Stop only if running
    # --------------------------------------------------------

    if container_running "${APP_NAME}"; then

        info "Menghentikan container lama..."

        $DOCKER stop \
            "${APP_NAME}" \
            >/dev/null 2>&1 ||
            true

    fi

    # --------------------------------------------------------
    # Remove container
    # --------------------------------------------------------

    info "Menghapus container lama..."

    $DOCKER rm \
        "${APP_NAME}" \
        >/dev/null 2>&1 ||
        true

    ok "Container lama dihapus."

fi


# ------------------------------------------------------------
# Start container
# ------------------------------------------------------------

info "Starting ${IMAGE}..."

if ! $DOCKER run -d \
    --name "${APP_NAME}" \
    --restart unless-stopped \
    -p "${WEBUI_PORT}:${WEBUI_INTERNAL_PORT}" \
    --add-host=host.docker.internal:host-gateway \
    -e "OLLAMA_BASE_URL=${OLLAMA_CONTAINER_API}" \
    -e "WEBUI_AUTH=true" \
    -e "WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}" \
    -v "${VOLUME_NAME}:/app/backend/data" \
    "${IMAGE}"
then

    error "Container Open WebUI gagal dibuat."

    echo ""
    echo "Docker error/log:"
    $DOCKER logs \
        "${APP_NAME}" \
        --tail 100 \
        2>&1 ||
        true

    exit 1

fi

ok "Container Open WebUI dibuat."


# ============================================================
# 14. FULL OPEN WEBUI DIAGNOSTICS
# ============================================================

separator "[14/14] FULL OPEN WEBUI DIAGNOSTICS"

sleep 3


# ============================================================
# Container status
# ============================================================

$DOCKER ps \
    --filter "name=${APP_NAME}" \
    --format \
    "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

CONTAINER_RUNNING=$(
    $DOCKER inspect \
        -f '{{.State.Running}}' \
        "${APP_NAME}" \
        2>/dev/null ||
        echo "false"
)

echo ""

if [ "${CONTAINER_RUNNING}" = "true" ]; then

    ok "Container Open WebUI RUNNING."

else

    error "Container Open WebUI tidak RUNNING."

    echo ""
    $DOCKER ps -a \
        --filter "name=${APP_NAME}" \
        --format \
        "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    $DOCKER logs \
        "${APP_NAME}" \
        --tail 100 \
        2>&1 ||
        true

fi


# ============================================================
# WebUI HTTP
# ============================================================

echo ""
info "Testing Open WebUI HTTP..."

WEBUI_READY=0

for i in $(seq 1 "${WEBUI_TIMEOUT}"); do

    if curl -fsS \
        --connect-timeout 2 \
        --max-time 5 \
        "http://127.0.0.1:${WEBUI_PORT}" \
        >/dev/null 2>&1
    then

        WEBUI_READY=1
        break

    fi

    printf "."
    sleep 1

done

echo ""

if [ "${WEBUI_READY}" -eq 1 ]; then

    ok "Open WebUI HTTP aktif."

else

    error "Open WebUI HTTP tidak merespons."

fi


# ============================================================
# Container environment
# ============================================================

echo ""
info "Checking OLLAMA_BASE_URL..."

CONTAINER_OLLAMA_URL=$(
    $DOCKER inspect \
        -f '{{range .Config.Env}}{{println .}}{{end}}' \
        "${APP_NAME}" \
        2>/dev/null |
    grep '^OLLAMA_BASE_URL=' |
    head -n 1 ||
    true
)

EXPECTED_OLLAMA_URL="OLLAMA_BASE_URL=${OLLAMA_CONTAINER_API}"

if [[ "${CONTAINER_OLLAMA_URL}" == "${EXPECTED_OLLAMA_URL}" ]]; then

    ok "OLLAMA_BASE_URL benar."

else

    error "OLLAMA_BASE_URL tidak sesuai."

    echo "  Expected:"
    echo "    ${EXPECTED_OLLAMA_URL}"

    echo "  Actual:"
    echo "    ${CONTAINER_OLLAMA_URL:-NOT_FOUND}"

fi


# ============================================================
# host.docker.internal
# ============================================================

echo ""
info "Testing host.docker.internal..."

DOCKER_HOST_GATEWAY=$(
    $DOCKER exec \
        "${APP_NAME}" \
        getent hosts host.docker.internal \
        2>/dev/null ||
        true
)

if [ -n "${DOCKER_HOST_GATEWAY}" ]; then

    ok "host.docker.internal dapat di-resolve."

    echo "  ${DOCKER_HOST_GATEWAY}"

else

    error "host.docker.internal tidak dapat di-resolve."

fi


# ============================================================
# Docker -> Ollama
# ============================================================

echo ""
info "Testing Docker -> Ollama..."

DOCKER_OLLAMA_OK=0


# ------------------------------------------------------------
# Method 1: Python
# ------------------------------------------------------------

if $DOCKER exec \
    "${APP_NAME}" \
    python -c "
import urllib.request
url='${OLLAMA_CONTAINER_API}/api/tags'
r=urllib.request.urlopen(url, timeout=10)
assert r.status == 200
" \
    >/dev/null 2>&1
then

    DOCKER_OLLAMA_OK=1

    ok "Docker -> host.docker.internal -> Ollama CONNECTED."

fi


# ------------------------------------------------------------
# Method 2: curl
# ------------------------------------------------------------

if [ "${DOCKER_OLLAMA_OK}" -eq 0 ]; then

    if $DOCKER exec \
        "${APP_NAME}" \
        curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        "${OLLAMA_CONTAINER_API}/api/tags" \
        >/dev/null 2>&1
    then

        DOCKER_OLLAMA_OK=1

        ok "Docker -> host.docker.internal -> Ollama CONNECTED via curl."

    fi

fi


# ============================================================
# Docker gateway test
# ============================================================

echo ""
info "Testing Docker gateway -> Ollama..."

GATEWAY_OLLAMA_OK=0

if [ -n "${DOCKER_GATEWAY}" ]; then

    echo "Gateway: ${DOCKER_GATEWAY}"

    if $DOCKER exec \
        "${APP_NAME}" \
        curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        "http://${DOCKER_GATEWAY}:${OLLAMA_PORT}/api/tags" \
        >/dev/null 2>&1
    then

        GATEWAY_OLLAMA_OK=1

        ok "Docker gateway -> Ollama CONNECTED."

    else

        warn "Docker gateway -> Ollama FAILED."

    fi

else

    warn "Docker gateway tidak diketahui."

fi


# ============================================================
# If both fail: diagnostic
# ============================================================

if [ "${DOCKER_OLLAMA_OK}" -eq 0 ]; then

    echo ""
    error "Docker -> Ollama FAILED."

    echo ""
    echo "Connection target:"
    echo "  ${OLLAMA_CONTAINER_API}"

    echo ""
    echo "Docker gateway:"
    echo "  ${DOCKER_GATEWAY:-UNKNOWN}"

    echo ""
    echo "Docker subnet:"
    echo "  ${DOCKER_SUBNET:-UNKNOWN}"

    echo ""
    echo "Ollama listener:"

    sudo ss -lntp 2>/dev/null |
        grep ":${OLLAMA_PORT} " ||
        true

    echo ""
    echo "Docker bridge:"

    ip addr show docker0 \
        2>/dev/null ||
        true

fi


# ============================================================
# Container -> Ollama tags
# ============================================================

echo ""
info "Testing Ollama API dari container..."

CONTAINER_TAGS_OK=0

if $DOCKER exec \
    "${APP_NAME}" \
    python -c "
import urllib.request
r=urllib.request.urlopen(
    '${OLLAMA_CONTAINER_API}/api/tags',
    timeout=10
)
assert r.status == 200
print(r.read().decode())
" \
    >/dev/null 2>&1
then

    CONTAINER_TAGS_OK=1

    ok "Container -> Ollama /api/tags BERHASIL."

else

    if $DOCKER exec \
        "${APP_NAME}" \
        curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        "${OLLAMA_CONTAINER_API}/api/tags" \
        >/dev/null 2>&1
    then

        CONTAINER_TAGS_OK=1

        ok "Container -> Ollama /api/tags BERHASIL via curl."

    else

        warn "Container -> Ollama /api/tags gagal."

    fi

fi


# ============================================================
# Container model inference
# ============================================================

echo ""
info "Testing Ollama model dari container..."

MODEL_TEST_OK=0

MODEL_TEST=$(
    $DOCKER exec \
        "${APP_NAME}" \
        python -c "
import json
import urllib.request

data=json.dumps({
    'model':'${MODEL}',
    'prompt':'Reply exactly OLLAMA_CONTAINER_OK',
    'stream':False
}).encode()

req=urllib.request.Request(
    '${OLLAMA_CONTAINER_API}/api/generate',
    data=data,
    headers={
        'Content-Type':'application/json'
    }
)

r=urllib.request.urlopen(
    req,
    timeout=90
)

if r.status != 200:
    raise SystemExit(1)

print(r.read().decode())
" \
        2>/dev/null ||
        true
)


if echo "${MODEL_TEST}" |
    grep -qi "OLLAMA_CONTAINER_OK"
then

    MODEL_TEST_OK=1

    ok "Container -> Ollama -> ${MODEL} BERHASIL."

elif [ -n "${MODEL_TEST}" ]; then

    MODEL_TEST_OK=1

    warn "Ollama merespons dari container."

    echo ""
    echo "${MODEL_TEST}" |
        head -c 1000

    echo ""

else

    warn "Inference dari container gagal."

fi


# ============================================================
# Open WebUI logs short check
# ============================================================

echo ""
info "Checking Open WebUI logs..."

WEBUI_LOGS=$(
    $DOCKER logs \
        "${APP_NAME}" \
        --tail 100 \
        2>&1 ||
        true
)

if echo "${WEBUI_LOGS}" |
    grep -qE \
    'HTTP/1.1" 200|HTTP/2" 200|GET / HTTP'
then

    ok "Open WebUI menghasilkan HTTP response."

else

    info "Belum ditemukan HTTP 200 pada log terbaru."

fi


# ============================================================
# Health
# ============================================================

echo ""
info "Container health..."

HEALTH=$(
    $DOCKER inspect \
        -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}NO_HEALTHCHECK{{end}}' \
        "${APP_NAME}" \
        2>/dev/null ||
        echo "UNKNOWN"
)

case "${HEALTH}" in

    healthy)

        ok "Health: healthy"
        ;;

    starting)

        warn "Health: starting"
        ;;

    unhealthy)

        error "Health: unhealthy"
        ;;

    NO_HEALTHCHECK)

        info "Image tidak menyediakan HEALTHCHECK."
        ;;

    *)

        warn "Health: ${HEALTH}"
        ;;

esac


# ============================================================
# FINAL REPORT
# ============================================================

separator "FINAL HEALTH REPORT"

echo ""


# ------------------------------------------------------------
# Ollama
# ------------------------------------------------------------

if [ "${OLLAMA_READY}" -eq 1 ]; then

    ok "OLLAMA           : ONLINE"

else

    error "OLLAMA           : OFFLINE"

fi


# ------------------------------------------------------------
# Model
# ------------------------------------------------------------

if ollama list |
    awk 'NR>1 {print $1}' |
    grep -Fxq "${MODEL}"
then

    ok "MODEL            : ${MODEL} AVAILABLE"

else

    error "MODEL            : ${MODEL} MISSING"

fi


# ------------------------------------------------------------
# Container
# ------------------------------------------------------------

if [ "${CONTAINER_RUNNING}" = "true" ]; then

    ok "OPEN WEBUI       : CONTAINER RUNNING"

else

    error "OPEN WEBUI       : CONTAINER STOPPED"

fi


# ------------------------------------------------------------
# WebUI
# ------------------------------------------------------------

if [ "${WEBUI_READY}" -eq 1 ]; then

    ok "WEBUI HTTP       : http://localhost:${WEBUI_PORT}"

else

    error "WEBUI HTTP       : NOT RESPONDING"

fi


# ------------------------------------------------------------
# Docker -> Ollama
# ------------------------------------------------------------

if [ "${DOCKER_OLLAMA_OK}" -eq 1 ]; then

    ok "WEBUI -> OLLAMA  : CONNECTED"

else

    error "WEBUI -> OLLAMA  : FAILED"

fi


# ------------------------------------------------------------
# API
# ------------------------------------------------------------

if [ "${CONTAINER_TAGS_OK}" -eq 1 ]; then

    ok "CONTAINER API    : CONNECTED"

else

    error "CONTAINER API    : FAILED"

fi


# ------------------------------------------------------------
# Model container test
# ------------------------------------------------------------

if [ "${MODEL_TEST_OK}" -eq 1 ]; then

    ok "CONTAINER MODEL  : WORKING"

else

    error "CONTAINER MODEL  : FAILED"

fi


# ============================================================
# Overall
# ============================================================

echo ""

if [ "${OLLAMA_READY}" -eq 1 ] &&
   [ "${CONTAINER_RUNNING}" = "true" ] &&
   [ "${WEBUI_READY}" -eq 1 ] &&
   [ "${DOCKER_OLLAMA_OK}" -eq 1 ] &&
   [ "${CONTAINER_TAGS_OK}" -eq 1 ] &&
   [ "${MODEL_TEST_OK}" -eq 1 ]
then

    echo "======================================================"
    echo ""
    ok "OLLAMA + OPEN WEBUI SIAP DIGUNAKAN."
    echo ""
    echo "Buka:"
    echo ""
    echo "    http://localhost:${WEBUI_PORT}"
    echo ""
    echo "Backend:"
    echo ""
    echo "    ${OLLAMA_CONTAINER_API}"
    echo ""
    echo "Model:"
    echo ""
    echo "    ${MODEL}"
    echo ""
    echo "======================================================"

else

    echo "======================================================"
    echo ""
    error "SISTEM BELUM SEPENUHNYA SEHAT."
    echo ""

    echo "Open WebUI log:"
    echo ""
    echo "    sudo docker logs ${APP_NAME} --tail 200"

    echo ""
    echo "Ollama log:"
    echo ""
    echo "    sudo journalctl -u ollama -n 100 --no-pager"

    echo ""
    echo "Docker network:"
    echo ""
    echo "    sudo docker network inspect bridge"

    echo ""
    echo "======================================================"

fi


# ============================================================
# FINAL LOG
# ============================================================

echo ""
echo "======================================================"
echo "                 OPEN WEBUI LOG"
echo "======================================================"

$DOCKER logs \
    "${APP_NAME}" \
    --tail 50 \
    2>&1 ||
    true


echo ""
echo "======================================================"
echo "                    SELESAI"
echo "======================================================"
