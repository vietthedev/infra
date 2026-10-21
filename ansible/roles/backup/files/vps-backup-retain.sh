#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/vps"
SETTINGS_FILE="/etc/vps-backup/settings.conf"

umask 077

# This file is managed by Ansible and writable only by root.
source "$SETTINGS_FILE"

mode="${1:---dry-run}"

case "$mode" in
    --dry-run|--apply) ;;
    *)
        echo "Usage: $0 [--dry-run|--apply]" >&2
        exit 2
        ;;
esac

if ! [[ "$BACKUP_KEEP_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid backup retention count" >&2
    exit 1
fi

if ! [[ "$BACKUP_MIN_AGE_HOURS" =~ ^[0-9]+$ ]]; then
    echo "Invalid minimum backup age" >&2
    exit 1
fi

[[ -d "$BACKUP_DIR" ]] || {
    echo "Backup directory missing" >&2
    exit 1
}

shopt -s nullglob

archives=( "$BACKUP_DIR"/vps-*.tar.gz )

if (( ${#archives[@]} == 0 )); then
    echo "No backup archives found"
    exit 0
fi

# ISO-like UTC timestamps sort newest first.
mapfile -t sorted < <(
    printf '%s\n' "${archives[@]}" | LC_ALL=C sort -r
)

valid=()

# Consider only our expected archive naming format.
for archive in "${sorted[@]}"; do
    name="${archive##*/}"

    [[ "$name" =~ ^vps-[0-9]{8}T[0-9]{6}Z\.tar\.gz$ ]] \
        || continue

    # Never prune if a recognized archive is incomplete.
    if [[ ! -f "${archive}.sha256" ]]; then
        echo "Missing checksum: $name" >&2
        echo "Refusing retention cleanup" >&2
        exit 1
    fi

    valid+=( "$archive" )
done

echo "Complete backups found: ${#valid[@]}"
echo "Keep newest: $BACKUP_KEEP_COUNT"
echo "Minimum deletion age: $BACKUP_MIN_AGE_HOURS hours"
echo "Mode: $mode"

now=$(date +%s)
minimum_age=$((BACKUP_MIN_AGE_HOURS * 3600))
removed=0

for ((i=BACKUP_KEEP_COUNT; i<${#valid[@]}; i++)); do
    archive="${valid[$i]}"
    name="${archive##*/}"

    modified=$(stat -c %Y -- "$archive")
    age=$((now - modified))

    if (( age < minimum_age )); then
        echo "Preserving recent archive: $name"
        continue
    fi

    if [[ "$mode" == "--dry-run" ]]; then
        echo "Would delete: $name"
    else
        rm -- "$archive" "${archive}.sha256"
        echo "Deleted: $name"
    fi

    removed=$((removed + 1))
done

echo "Eligible archive pairs: $removed"

