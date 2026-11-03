# linux-gdrive-dotenv-backup-recovery

Encrypt listed `.env` files with **restic**, store only ciphertext on Google
Drive via **rclone**, restore when you need them, and (optionally) run on an
hourly **systemd user timer**.

Drive never sees plaintext. The same script works on a laptop and a server.

## Install

```bash
git clone https://github.com/austenstrine/linux-gdrive-dotenv-backup-recovery.git \
  ~/src/linux-gdrive-dotenv-backup-recovery
chmod +x ~/src/linux-gdrive-dotenv-backup-recovery/env-backup.sh

# optional: put a wrapper on PATH
mkdir -p ~/bin
ln -sf ~/src/linux-gdrive-dotenv-backup-recovery/env-backup.sh ~/bin/env-backup.sh
```

Dependencies (once per host):

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y restic rclone

# Fedora
sudo dnf install -y restic rclone
```

## rclone + restic (one-time)

1. Configure an rclone remote named `gdrive` that can write to Drive
   (`rclone config`, then `rclone lsd gdrive:`).
2. Choose a restic password and keep it in a password manager.
3. Create the password file (mode 600):

```bash
mkdir -p ~/.config/env-backup
chmod 700 ~/.config/env-backup
printf '%s' 'YOUR_RESTIC_PASSWORD' > ~/.config/env-backup/restic.pass
chmod 600 ~/.config/env-backup/restic.pass
```

4. Initialize the remote repo the first time (optional; restic creates it on
   first backup if you prefer):

```bash
export RESTIC_REPOSITORY=rclone:gdrive:env-restic
export RESTIC_PASSWORD_FILE=$HOME/.config/env-backup/restic.pass
restic init
```

Defaults:

| Variable | Default |
|----------|---------|
| `RESTIC_REPOSITORY` | `rclone:gdrive:env-restic` |
| `RESTIC_PASSWORD_FILE` | `~/.config/env-backup/restic.pass` |
| `ENV_BACKUP_STATE_DIR` | `~/.config/env-backup` (holds `last-hash`) |

Never commit `restic.pass`, rclone tokens, or real `.env` files.

## `ENV_BACKUP_FILES`

Space-separated **absolute** paths of files to snapshot.

```bash
export ENV_BACKUP_FILES="$HOME/my-app/.env $HOME/my-app/apps/api/.env"
env-backup.sh backup
```

If unset, the script backs up `$PWD/.env` only. Missing paths are skipped;
backup fails if none exist.

## Commands

```bash
env-backup.sh backup                 # skip when file hashes unchanged
env-backup.sh snapshots
env-backup.sh restore ~/recovered-env
```

Retention on backup: keep 14 daily / 8 weekly / 12 monthly, then prune.
If Drive rate-limits prune, snapshots are still saved.

## Systemd user timer

```bash
mkdir -p ~/.config/systemd/user ~/.config/env-backup
TOOL=~/src/linux-gdrive-dotenv-backup-recovery

cp "$TOOL/systemd/env-backup.timer" ~/.config/systemd/user/
cp "$TOOL/systemd/env-backup.service" ~/.config/systemd/user/
# edit ExecStart to "$TOOL/env-backup.sh backup"
# and add Environment=ENV_BACKUP_FILES=… for your project
# or keep ExecStart=%h/bin/env-backup.sh backup if you use the symlink

systemctl --user daemon-reload
systemctl --user enable --now env-backup.timer
# optional: timer without interactive login
sudo loginctl enable-linger "$(id -un)"
```

`systemctl --user list-timers` should show `env-backup.timer`.

## Restore

```bash
export RESTIC_PASSWORD_FILE=$HOME/.config/env-backup/restic.pass
export RESTIC_REPOSITORY=rclone:gdrive:env-restic
env-backup.sh snapshots
env-backup.sh restore ~/recovered-env
# files land under ~/recovered-env with their original absolute paths mirrored
```

Copy recovered files back into the project carefully; do not overwrite a live
`.env` without checking.

## Portfolio / deploy glue

This repo is the generic CLI + unit templates. Project-specific installers
(for example Place et Marque’s `ops/deploy/ensure-env-backup.sh` and
`push-env-backup-secrets.sh`) stay in the consumer repo and should resolve
this checkout via `ENV_BACKUP_HOME`, a sibling clone, `~/src/…`, or
`~/bin/env-backup.sh`.
