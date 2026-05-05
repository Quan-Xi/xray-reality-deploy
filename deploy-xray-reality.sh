#!/usr/bin/env bash
set -Eeuo pipefail

# Xray-core + VLESS + REALITY + Vision one-file deploy script.
# Target: Debian/Ubuntu/CentOS/RHEL/Fedora/OpenSUSE systems with systemd.
# Usage on VPS:
#   sudo bash deploy-xray-reality.sh
#
# Optional environment overrides:
#   DEPLOY_MODE=direct PUBLIC_HOST=proxy.example.com bash deploy-xray-reality.sh
#   DEPLOY_MODE=nginx PUBLIC_HOST=proxy.example.com SNI=www.microsoft.com bash deploy-xray-reality.sh

DEPLOY_MODE="${DEPLOY_MODE:-}"
PORT="${PORT:-}"
LISTEN="${LISTEN:-}"
PUBLIC_HOST="${PUBLIC_HOST:-}"
PUBLIC_PORT="${PUBLIC_PORT:-}"
SNI="${SNI:-www.microsoft.com}"
DEST="${DEST:-${SNI}:443}"
SPIDERX="${SPIDERX:-/}"
CLIENT_NAME="${CLIENT_NAME:-shadowrocket}"
INSTALL_USER="${INSTALL_USER:-nobody}"
OPEN_FIREWALL="${OPEN_FIREWALL:-1}"
XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"

XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"

prompt_deploy_mode() {
  if [[ -z "$DEPLOY_MODE" ]]; then
    if [[ -t 0 ]]; then
      cat <<EOF
Select deploy mode:
  1) Direct public listen, no Nginx
  2) Behind Nginx SNI stream forwarding
EOF
      local mode
      read -r -p "Mode [1]: " mode
      mode="${mode:-1}"
      case "$mode" in
        1) DEPLOY_MODE="direct" ;;
        2) DEPLOY_MODE="nginx" ;;
        *)
          echo "error: invalid deploy mode: $mode" >&2
          exit 1
          ;;
      esac
    else
      DEPLOY_MODE="direct"
    fi
  fi

  case "$DEPLOY_MODE" in
    direct)
      LISTEN="${LISTEN:-0.0.0.0}"
      PORT="${PORT:-443}"
      PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"
      ;;
    nginx)
      LISTEN="${LISTEN:-127.0.0.1}"
      PORT="${PORT:-10443}"
      PUBLIC_PORT="${PUBLIC_PORT:-443}"
      ;;
    *)
      echo "error: DEPLOY_MODE must be direct or nginx." >&2
      exit 1
      ;;
  esac

  if [[ -t 0 && -z "$PUBLIC_HOST" ]]; then
    read -r -p "Public host for clients, leave empty to auto-detect server IP: " PUBLIC_HOST
  fi
}

validate_port() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 65535 )); then
    echo "error: $name must be a TCP port between 1 and 65535." >&2
    exit 1
  fi
}

validate_json_string() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *\"* || "$value" == *\\* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "error: $name cannot contain quotes, backslashes, or newlines." >&2
    exit 1
  fi
}

validate_inputs() {
  validate_port "PORT" "$PORT"
  validate_port "PUBLIC_PORT" "$PUBLIC_PORT"

  validate_json_string "LISTEN" "$LISTEN"
  validate_json_string "PUBLIC_HOST" "$PUBLIC_HOST"
  validate_json_string "SNI" "$SNI"
  validate_json_string "DEST" "$DEST"
  validate_json_string "SPIDERX" "$SPIDERX"
  validate_json_string "CLIENT_NAME" "$CLIENT_NAME"
}

need_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "error: please run as root, for example: sudo bash $0" >&2
    exit 1
  fi
}

need_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "error: systemd was not found. This script expects a systemd-based VPS." >&2
    exit 1
  fi
}

install_base_tools() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl ca-certificates unzip openssl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates unzip openssl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates unzip openssl
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl ca-certificates unzip openssl
  else
    echo "error: unsupported package manager. Please install curl, ca-certificates, unzip and openssl manually." >&2
    exit 1
  fi
}

install_xray() {
  local installer
  installer="$(mktemp /tmp/xray-install.XXXXXX.sh)"
  curl -fsSL "$XRAY_INSTALL_URL" -o "$installer"
  echo "Downloaded official Xray installer to: $installer"
  bash "$installer" install --version "$XRAY_VERSION" --without-logfiles -u "$INSTALL_USER"
}

open_firewall_port() {
  [[ "$OPEN_FIREWALL" == "1" ]] || return 0

  local firewall_port="$PUBLIC_PORT"

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi active; then
    ufw allow "${firewall_port}/tcp"
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${firewall_port}/tcp"
    firewall-cmd --reload
  fi
}

write_config() {
  mkdir -p "$CONFIG_DIR"

  local uuid private_key public_key short_id
  uuid="$(xray uuid)"
  short_id="$(openssl rand -hex 8)"

  local keypair
  keypair="$(xray x25519)"
  private_key="$(printf '%s\n' "$keypair" | awk -F': ' '/^Private[ ]?[Kk]ey/ {print $2}')"
  public_key="$(printf '%s\n' "$keypair" | awk -F': ' '/^(Public[ ]?[Kk]ey|Password \\(PublicKey\\))/ {print $2}')"

  if [[ -z "$private_key" || -z "$public_key" ]]; then
    echo "error: failed to generate REALITY x25519 keypair." >&2
    exit 1
  fi

  local backup_file=""
  if [[ -f "$CONFIG_FILE" ]]; then
    backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    echo "Backed up existing config to: $backup_file"
  fi

  umask 077
  cat >"$CONFIG_FILE" <<JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "${LISTEN}",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision",
            "email": "${CLIENT_NAME}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${private_key}",
          "shortIds": [
            "${short_id}"
          ],
          "spiderX": "${SPIDERX}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
JSON

  if ! xray run -test -config "$CONFIG_FILE"; then
    if [[ -n "$backup_file" ]]; then
      cp "$backup_file" "$CONFIG_FILE"
      echo "Restored previous config from: $backup_file" >&2
    fi
    echo "error: generated Xray config did not pass validation." >&2
    exit 1
  fi

  systemctl daemon-reload
  systemctl enable --now xray
  systemctl restart xray
  open_firewall_port

  local public_host encoded_name encoded_spiderx share_link
  if [[ -n "$PUBLIC_HOST" ]]; then
    public_host="$PUBLIC_HOST"
  else
    public_host="$(curl -fsS4 --max-time 8 https://api.ipify.org || hostname -I | awk '{print $1}')"
  fi
  encoded_name="$(printf '%s' "$CLIENT_NAME" | sed 's/ /%20/g')"
  if [[ "$SPIDERX" == "/" ]]; then
    encoded_spiderx="%2F"
  else
    encoded_spiderx="$SPIDERX"
  fi
  share_link="vless://${uuid}@${public_host}:${PUBLIC_PORT}?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${public_key}&sid=${short_id}&spx=${encoded_spiderx}#${encoded_name}"

  cat <<EOF

Xray REALITY deployment finished.

Shadowrocket import link:
${share_link}

Manual settings:
  Type: VLESS
  Address: ${public_host}
  Port: ${PUBLIC_PORT}
  UUID: ${uuid}
  Encryption: none
  Flow: xtls-rprx-vision
  Transport: TCP
  TLS/Security: REALITY
  SNI/ServerName: ${SNI}
  PublicKey: ${public_key}
  ShortID: ${short_id}
  Fingerprint: chrome
  SpiderX: ${SPIDERX}

Server files:
  Config: ${CONFIG_FILE}
  Service: xray

Server listen:
  Listen: ${LISTEN}
  Local port: ${PORT}

Useful commands:
  systemctl status xray
  journalctl -u xray -e --no-pager
EOF
}

main() {
  need_root
  need_systemd
  prompt_deploy_mode
  validate_inputs
  install_base_tools
  install_xray
  write_config
}

main "$@"
