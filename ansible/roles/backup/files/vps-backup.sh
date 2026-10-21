#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/vps"
PATHS_FILE="/etc/vps-backup/paths"

umask 077

SETTINGS_FILE="/etc/vps-backup/settings.conf"

# Root-owned, Ansible-managed settings.
source "$SETTINGS_FILE"

# Prevent concurrent backup executions
exec 9>/run/lock/vps-backup.lock

if ! flock -n 9; then
    echo "Another VPS backup is already running" >&2
    exit 1
fi

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
archive="$BACKUP_DIR/vps-$timestamp.tar.gz"
temporary=$(mktemp "$BACKUP_DIR/.backup-XXXXXXXX.tar.gz")

trap 'rm -f "$temporary"' EXIT

mapfile -t sources < "$PATHS_FILE"

if (( ${#sources[@]} == 0 )); then
    echo "No backup sources configured" >&2
    exit 1
fi

relative_paths=()

for path in "${sources[@]}"; do
    if [[ "$path" != /* || ! -e "$path" ]]; then
        echo "Invalid or missing path: $path" >&2
        exit 1
    fi

    relative_paths+=("${path#/}")
done

# Estimate the uncompressed source size.
estimated_bytes=$(
    du -sb -- "${sources[@]}" |
        awk '{ total += $1 } END { printf "%.0f\n", total }'
)

# Available disk space on the backup filesystem.
available_bytes=$(
    df -PB1 "$BACKUP_DIR" |
        awk 'NR == 2 { print $4 }'
)

# Reserve some free space after the backup.
minimum_free_bytes=$((BACKUP_MIN_FREE_MB * 1024 * 1024))
required_bytes=$((estimated_bytes + minimum_free_bytes))

if (( available_bytes < required_bytes )); then
    echo "Insufficient disk space for a safe backup" >&2
    echo "Estimated source size: $estimated_bytes bytes" >&2
    echo "Available space: $available_bytes bytes" >&2
    echo "Reserved free space: $minimum_free_bytes bytes" >&2
    exit 1
fi

echo "Creating backup: $archive"

tar -C / -czf "$temporary" -- "${relative_paths[@]}"

# Verify archive readability
tar -tzf "$temporary" > /dev/null

if [[ -e "$archive" || -e "${archive}.sha256" ]]; then
    echo "Backup timestamp collision: $archive" >&2
    exit 1
fi

# Move into place only after successful creation
mv "$temporary" "$archive"

# Generate checksum
(
    cd "$BACKUP_DIR"
    sha256sum "$(basename "$archive")" \
        > "$(basename "$archive").sha256"
)

echo "Backup completed successfully:"
ls -lh "$archive"

# Verify the checksum before considering retention.
(
    cd "$BACKUP_DIR"
    sha256sum -c -- "$(basename "$archive").sha256"
)

# Run cleanup only when explicitly enabled.
if [[ "$BACKUP_ENABLE_RETENTION" == "1" ]]; then
    /usr/local/sbin/vps-backup-retain --apply
fi

