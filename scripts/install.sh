#!/bin/bash
# Install gpg-wsl: shared YubiKey scdaemon for two users via socat proxy.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$HERE")
. "$HERE/lib.sh"

require_root install
require_user "$PRIMARY_USER"
require_user "$SECONDARY_USER"

echo "[1/8] apt packages"
APT_PKGS="pcscd scdaemon gnupg2 yubikey-manager socat"
MISSING=$(dpkg-query -W -f='${Package} ${Status}\n' $APT_PKGS 2>/dev/null | awk '$NF!="installed"{print $1}'; \
          for p in $APT_PKGS; do dpkg-query -W "$p" >/dev/null 2>&1 || echo "$p"; done) || true
MISSING=$(echo "$MISSING" | sort -u | grep -v '^$' || true)
if [ -n "$MISSING" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
fi

echo "[2/8] groups"
for u in "$PRIMARY_USER" "$SECONDARY_USER"; do
    usermod -aG scard,plugdev "$u"
done

echo "[3/8] polkit rule"
install -m 644 -o root -g root "$PROJECT_DIR/files/polkit/45-pcscd-scard.rules" /etc/polkit-1/rules.d/45-pcscd-scard.rules

echo "[4/8] wrapper /usr/local/bin/scdaemon-proxy.sh"
TMP=$(mktemp)
render "$PROJECT_DIR/files/bin/scdaemon-proxy.sh.in" "$TMP"
install -m 755 -o root -g root "$TMP" /usr/local/bin/scdaemon-proxy.sh
rm -f "$TMP"

echo "[5/8] sudoers rule /etc/sudoers.d/96-yubikey-proxy"
TMP=$(mktemp)
render "$PROJECT_DIR/files/sudoers/96-yubikey-proxy.in" "$TMP"
install -m 440 -o root -g root "$TMP" /etc/sudoers.d/96-yubikey-proxy
rm -f "$TMP"
visudo -cf /etc/sudoers.d/96-yubikey-proxy

echo "[6/8] scdaemon.conf (primary=$PRIMARY_USER) and gpg-agent.conf (secondary=$SECONDARY_USER)"
install -d -o "$PRIMARY_USER" -g "$PRIMARY_USER" -m 700 /home/"$PRIMARY_USER"/.gnupg
install -d -o "$SECONDARY_USER" -g "$SECONDARY_USER" -m 700 /home/"$SECONDARY_USER"/.gnupg

install -m 600 -o "$PRIMARY_USER" -g "$PRIMARY_USER" \
    "$PROJECT_DIR/files/gnupg/scdaemon.conf.primary" \
    /home/"$PRIMARY_USER"/.gnupg/scdaemon.conf

TMP=$(mktemp)
render "$PROJECT_DIR/files/gnupg/gpg-agent.conf.secondary.in" "$TMP"
# preserve any other settings the user may have in gpg-agent.conf
TARGET=/home/"$SECONDARY_USER"/.gnupg/gpg-agent.conf
touch "$TARGET"; chown "$SECONDARY_USER":"$SECONDARY_USER" "$TARGET"; chmod 600 "$TARGET"
sed -i '/^scdaemon-program/d' "$TARGET"
cat "$TMP" >> "$TARGET"
rm -f "$TMP"

# SECONDARY_USER does not need its own scdaemon.conf - the proxy never reads it; leave whatever is there

echo "[7/8] .bashrc snippet for both users"
add_bashrc_snippet "$PRIMARY_USER"
add_bashrc_snippet "$SECONDARY_USER"

echo "[8/8] restart agents & pcscd"
sudo -u "$PRIMARY_USER"   gpgconf --kill all 2>/dev/null || true
sudo -u "$SECONDARY_USER" gpgconf --kill all 2>/dev/null || true
systemctl stop pcscd.service pcscd.socket 2>/dev/null || true
systemctl start pcscd.socket
# warm up primary scdaemon so the socket exists for secondary's first call
sudo -u "$PRIMARY_USER" gpg --card-status >/dev/null 2>&1 || true

echo "install done. run 'make status' to verify."
