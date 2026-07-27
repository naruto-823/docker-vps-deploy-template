#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root: sudo DEPLOY_PUBLIC_KEY='ssh-ed25519 ...' bash bootstrap-server.sh" >&2
  exit 1
fi
if [[ ! "${DEPLOY_USER}" =~ ^[a-z_][a-z0-9_-]{1,30}$ ]]; then
  echo "Invalid DEPLOY_USER" >&2
  exit 1
fi
if [[ "${DEPLOY_PUBLIC_KEY:-}" != ssh-ed25519\ * && "${DEPLOY_PUBLIC_KEY:-}" != ssh-rsa\ * ]]; then
  echo "DEPLOY_PUBLIC_KEY must contain one SSH public key" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git ufw
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
printf '%s\n' "$DEPLOY_PUBLIC_KEY" > "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/apps"

if ! swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
  if [ ! -e /swapfile ]; then
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Bootstrap complete. GitHub secret DEPLOY_USER should be: $DEPLOY_USER"
echo "Docker group access becomes active on the next SSH login."
