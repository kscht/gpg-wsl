#!/bin/bash
# Check the state of the gpg-wsl install.
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$HERE")
. "$HERE/lib.sh"

ok()   { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33m!!\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mERR\033[0m %s\n' "$1"; }

check_file() {
    if [ -e "$1" ]; then ok "$2: $1"; else fail "$2 missing: $1"; fi
}

echo "== gpg-wsl status (primary=$PRIMARY_USER, secondary=$SECONDARY_USER) =="

check_file /etc/polkit-1/rules.d/45-pcscd-scard.rules "polkit rule"
check_file /etc/sudoers.d/96-yubikey-proxy             "sudoers rule"
check_file /usr/local/bin/scdaemon-proxy.sh            "wrapper"
check_file /home/$PRIMARY_USER/.gnupg/scdaemon.conf    "primary scdaemon.conf"
check_file /home/$SECONDARY_USER/.gnupg/gpg-agent.conf "secondary gpg-agent.conf"

if command -v pcscd >/dev/null && systemctl is-active pcscd.socket >/dev/null 2>&1; then
    ok "pcscd.socket active"
else
    warn "pcscd.socket not active"
fi

if lsusb 2>/dev/null | grep -qi yubi; then
    ok "YubiKey visible on USB"
else
    warn "YubiKey not visible on USB (run 'usbipd attach' from PowerShell)"
fi

echo
echo "-- card status under $PRIMARY_USER --"
sudo -u "$PRIMARY_USER" gpg --card-status 2>&1 | head -4 || true
echo
echo "-- card status under $SECONDARY_USER (via proxy) --"
sudo -u "$SECONDARY_USER" gpg --card-status 2>&1 | head -4 || true
