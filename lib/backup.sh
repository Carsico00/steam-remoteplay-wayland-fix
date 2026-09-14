#!/usr/bin/env bash
# backup.sh - verifiable, restorable backups of anything we are about to touch.
#
# Every backup is a plain file copy under $BACKUP_DIR plus one line appended
# to $BACKUP_DIR/manifest.tsv recording what it was, when, its hash and the
# Steam build id at the time. We never overwrite or delete a backup; restore
# always reads the most recent manifest entry for a given kind.

MANIFEST="$BACKUP_DIR/manifest.tsv"

backup_init() {
    ensure_dirs
    [[ -f "$MANIFEST" ]] || printf 'timestamp\tkind\tsource_path\tbackup_path\tsha256\tsteam_build_id\n' > "$MANIFEST"
}

# backup_create <kind> <source_path>
# kind: pristine-real | foreign-wrapper
# Prints the backup file path on stdout.
backup_create() {
    local kind="$1" src="$2"
    backup_init
    [[ -f "$src" ]] || { die "backup_create: source not found: $src"; }
    local ts hash dst build
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    hash=$(sha256_of "$src")
    build=$(detect_steam_build_id 2>/dev/null || true)
    dst="$BACKUP_DIR/${kind}.${ts}.bak"
    cp -p "$src" "$dst"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$kind" "$src" "$dst" "$hash" "${build:-unknown}" >> "$MANIFEST"
    echo "$dst"
}

# backup_latest <kind> -> prints the backup_path of the newest matching entry
backup_latest() {
    local kind="$1"
    [[ -f "$MANIFEST" ]] || return 1
    awk -F'\t' -v k="$kind" '$2==k{line=$4} END{if(line) print line}' "$MANIFEST"
}

backup_latest_hash() {
    local kind="$1"
    [[ -f "$MANIFEST" ]] || return 1
    awk -F'\t' -v k="$kind" '$2==k{h=$5} END{if(h) print h}' "$MANIFEST"
}

# backup_has <kind> -> success if at least one backup of this kind exists
backup_has() {
    local latest
    latest=$(backup_latest "$1")
    [[ -n "$latest" && -f "$latest" ]]
}

# restore_from_backup <kind> <dest_path>
# Copies the newest backup of <kind> to <dest_path>, verifies the hash and
# restores the executable bit. Does nothing (returns 1) if no backup exists.
restore_from_backup() {
    local kind="$1" dest="$2" src expected actual
    src=$(backup_latest "$kind") || return 1
    [[ -n "$src" && -f "$src" ]] || return 1
    expected=$(backup_latest_hash "$kind")
    cp -p "$src" "$dest"
    chmod +x "$dest" 2>/dev/null || true
    actual=$(sha256_of "$dest")
    [[ "$actual" == "$expected" ]]
}

backup_list() {
    backup_init
    column -t -s $'\t' "$MANIFEST" 2>/dev/null || cat "$MANIFEST"
}
