#!/usr/bin/env bash
# Encrypted .env snapshots to Google Drive via restic + rclone.
# Drive only ever sees ciphertext.
#
# Same behavior on any host: hashes the listed .env files, skips when
# unchanged, otherwise restic backup + retention prune.
#
# Usage:
#   env-backup.sh [backup|snapshots|restore [target]]
#
# Config (env overrides):
#   RESTIC_REPOSITORY     default rclone:gdrive:env-restic
#   RESTIC_PASSWORD_FILE  default ~/.config/env-backup/restic.pass
#   ENV_BACKUP_FILES      space-separated absolute paths (recommended)
#                         default: $PWD/.env
#   ENV_BACKUP_STATE_DIR  default ~/.config/env-backup
set -euo pipefail

REPO="${RESTIC_REPOSITORY:-rclone:gdrive:env-restic}"
PASS="${RESTIC_PASSWORD_FILE:-$HOME/.config/env-backup/restic.pass}"
STATE_DIR="${ENV_BACKUP_STATE_DIR:-$HOME/.config/env-backup}"
HASH_FILE="$STATE_DIR/last-hash"

export RESTIC_REPOSITORY="$REPO"
export RESTIC_PASSWORD_FILE="$PASS"
export RCLONE_TPSLIMIT="${RCLONE_TPSLIMIT:-8}"
export RCLONE_RETRIES="${RCLONE_RETRIES:-10}"

if [[ -n "${ENV_BACKUP_FILES-}" ]]; then
	# shellcheck disable=SC2206
	FILES=($ENV_BACKUP_FILES)
else
	FILES=("$PWD/.env")
fi

if [[ ! -f "$PASS" ]]; then
	echo "Missing restic password file: $PASS" >&2
	echo "See README.md in linux-gdrive-dotenv-backup-recovery" >&2
	exit 1
fi

files_hash() {
	local f
	for f in "${FILES[@]}"; do
		if [[ -f "$f" ]]; then
			printf '%s ' "$f"
			sha256sum -- "$f"
		else
			printf '%s MISSING\n' "$f"
		fi
	done
}

cmd="${1:-backup}"

case "$cmd" in
	backup)
		mkdir -p "$STATE_DIR"
		chmod 700 "$STATE_DIR"
		current="$(files_hash)"
		if [[ -f "$HASH_FILE" ]] && [[ "$current" == "$(cat "$HASH_FILE")" ]]; then
			echo "No .env changes since last backup; skipping."
			exit 0
		fi
		existing=()
		for f in "${FILES[@]}"; do
			if [[ -f "$f" ]]; then
				existing+=("$f")
			else
				echo "skip missing: $f" >&2
			fi
		done
		if [[ ${#existing[@]} -eq 0 ]]; then
			echo "No .env files to back up." >&2
			exit 1
		fi
		restic backup -- "${existing[@]}"
		printf '%s' "$current" > "$HASH_FILE"
		chmod 600 "$HASH_FILE"
		if ! restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune; then
			echo "prune skipped (Drive busy or rate-limited); snapshots are still saved." >&2
		fi
		echo "Backup finished."
		;;
	snapshots)
		restic snapshots
		;;
	restore)
		target="${2:-$HOME/recovered-env}"
		mkdir -p "$target"
		restic restore latest --target "$target"
		echo "Restored latest snapshot under $target"
		;;
	*)
		echo "Usage: $0 [backup|snapshots|restore [target]]" >&2
		exit 1
		;;
esac
