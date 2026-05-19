#!/bin/bash
# Uninstall gpg-wsl: remove everything install.sh placed.
# Does NOT remove packages (pcscd/socat/etc) and does NOT touch user keyrings.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$HERE")
. "$HERE/lib.sh"

require_root uninstall

echo "[1/6] sudoers rule"
rm -f /etc/sudoers.d/96-yubikey-proxy

echo "[2/6] wrapper"
rm -f /usr/local/bin/scdaemon-proxy.sh

echo "[3/6] polkit rule"
rm -f /etc/polkit-1/rules.d/45-pcscd-scard.rules

echo "[4/6] scdaemon.conf (primary) and scdaemon-program line (secondary)"
rm -f /home/"$PRIMARY_USER"/.gnupg/scdaemon.conf
TARGET=/home/"$SECONDARY_USER"/.gnupg/gpg-agent.conf
[ -f "$TARGET" ] && sed -i '\|^scdaemon-program /usr/local/bin/scdaemon-proxy.sh$|d' "$TARGET"

echo "[5/6] .bashrc snippet"
remove_bashrc_snippet "$PRIMARY_USER"
remove_bashrc_snippet "$SECONDARY_USER"

echo "[6/6] kill agents, restart pcscd"
sudo -u "$PRIMARY_USER"   gpgconf --kill all 2>/dev/null || true
sudo -u "$SECONDARY_USER" gpgconf --kill all 2>/dev/null || true
systemctl stop pcscd.service pcscd.socket 2>/dev/null || true
systemctl start pcscd.socket 2>/dev/null || true

echo "uninstall done."
