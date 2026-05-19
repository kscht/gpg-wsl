# Shared helpers for install/uninstall/status.
# Expects env: PRIMARY_USER, SECONDARY_USER, PROJECT_DIR

set -e

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "must run as root (use: sudo make $1)" >&2
        exit 1
    fi
}

require_user() {
    if ! id "$1" >/dev/null 2>&1; then
        echo "user not found: $1" >&2
        exit 1
    fi
}

primary_uid() { id -u "$PRIMARY_USER"; }

render() {
    # render template: <src> <dst> — substitutes @PRIMARY_USER@/@SECONDARY_USER@/@PRIMARY_UID@
    local src=$1 dst=$2 uid
    uid=$(primary_uid)
    sed \
        -e "s|@PRIMARY_USER@|$PRIMARY_USER|g" \
        -e "s|@SECONDARY_USER@|$SECONDARY_USER|g" \
        -e "s|@PRIMARY_UID@|$uid|g" \
        "$src" > "$dst"
}

add_bashrc_snippet() {
    local user=$1 rc snippet
    rc=/home/$user/.bashrc
    snippet=$PROJECT_DIR/files/gnupg/bashrc.snippet
    [ -f "$rc" ] || { touch "$rc"; chown "$user":"$user" "$rc"; }
    if ! grep -qF 'BEGIN gpg-wsl' "$rc"; then
        cat "$snippet" >> "$rc"
        chown "$user":"$user" "$rc"
    fi
}

remove_bashrc_snippet() {
    local user=$1 rc
    rc=/home/$user/.bashrc
    [ -f "$rc" ] || return 0
    sed -i '/^# BEGIN gpg-wsl/,/^# END gpg-wsl/d' "$rc"
    chown "$user":"$user" "$rc"
}
