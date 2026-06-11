# OCI ARM Provision Bot

Telegram-controlled watchdog for retrying Oracle Cloud Infrastructure Ampere ARM instance provisioning.

The bot runs on a small OCI x86 instance and repeatedly attempts to create an Always Free compatible ARM instance. Status, reports, logs, and control commands are handled through Telegram.

## Goal

The goal is to automatically retry creation of an OCI Ampere ARM instance until capacity becomes available.

Target instance:

- Shape: VM.Standard.A1.Flex
- OCPU: 1
- RAM: 6 GB
- Boot volume: 50 GB
- OS: Ubuntu 24.04 ARM / aarch64

## Current features

- Telegram command controller
- ARM provisioning retry loop
- OCI CLI integration
- Daily report at 07:00 Europe/Helsinki time
- Runtime status via Telegram
- Log inspection via Telegram
- Safe `.env.example`
- Runtime state and logs excluded from Git

## Directory structure

```text
.
├── control
│   └── bot_control.sh
├── daemon
│   └── provision_arm.sh
├── infra-tools
│   ├── tg_receive.sh
│   └── tg_send.sh
├── logs
├── state
├── tasks
│   └── report.sh
├── .env.example
└── .gitignore
```

## Main components

### control/bot_control.sh

Main Telegram controller.

Responsibilities:

- sends startup notification
- polls Telegram updates
- validates chat id
- dispatches Telegram commands
- runs daily report after 07:00 Europe/Helsinki time
- updates Telegram offset
- checks stale `provision_arm` PID in `/status`

### daemon/provision_arm.sh

Long-running worker that tries to launch an OCI ARM instance.

Responsibilities:

- finds latest Ubuntu 24.04 ARM image
- launches `VM.Standard.A1.Flex` instance
- uses 1 OCPU and 6 GB RAM
- uses 50 GB boot volume
- retries every 300 seconds on failure
- updates `state/stats.json`
- sends Telegram notification on success

### tasks/report.sh

One-shot report task.

Responsibilities:

- reads `state/stats.json`
- reads `state/processes.json`
- sends report to Telegram

### infra-tools/tg_send.sh

Low-level Telegram send wrapper.

Responsibilities:

- reads Telegram configuration from `.env`
- sends one Telegram message
- logs Telegram API response

### infra-tools/tg_receive.sh

Low-level Telegram `getUpdates` wrapper.

Responsibilities:

- reads Telegram configuration from `.env`
- calls Telegram `getUpdates`
- supports offset handling
- prints raw JSON response for `bot_control.sh`

## Environment variables

Create `.env` based on `.env.example`.

Required variables:

```text
TG_BOT_TOKEN=
TG_CHAT_ID=
GEMINI_API=

OCI_COMPARTMENT_ID=
OCI_AD=
OCI_SUBNET_ID=
OCI_SSH_PUBLIC_KEY=
```

Do not commit `.env`.

## Telegram commands

```text
/ping
/report
/status
/start provision_arm
/stop provision_arm
/restart provision_arm
/logs
/logs provision_arm
/logs provision_arm 20
/logs all
/logs all 20
```

### /ping

Checks that `bot_control.sh` is running and responding.

Expected response:

```text
pong
```

### /report

Runs `tasks/report.sh` and sends a status report to Telegram.

### /status

Shows current runtime state and next scheduled report time.

Example response:

```text
RUNNING:
- provision_arm.sh (PID 1234)

SCHEDULED:
- 12.06.26 - 07:00:00 - report.sh
```

### /start provision_arm

Starts `daemon/provision_arm.sh` if it is not already running.

### /stop provision_arm

Stops `daemon/provision_arm.sh` if it is running.

### /restart provision_arm

Stops existing `daemon/provision_arm.sh` if alive, then starts a new one.

### /logs

Shows usage instructions for log inspection.

### /logs <target>

Shows the latest log for the selected target using the default line count of 5.

Supported targets:

- `bot_control`
- `provision_arm`
- `report`
- `tg_send`
- `tg_receive`
- `all`

### /logs <target> <lines>

Shows the requested number of lines from the latest log file.

Examples:

```text
/logs provision_arm 20
/logs all 2
```

## Logs

Logs are written under:

```text
logs/
```

Log files are ignored by Git.

## Runtime state

Runtime state is stored under:

```text
state/
```

State files are ignored by Git.

The main state files are:

```text
state/processes.json
state/stats.json
state/tg_offset.txt
```

## Git safety

The repository must not include:

- `.env`
- `logs/`
- `state/`
- private keys
- OCI config
- SSH keys

The `.gitignore` file should keep secrets, logs, and runtime state out of Git.

## Development notes

This project is intentionally Bash-based and lightweight.

The current architecture is expected to be refactored so that `control/bot_control.sh` becomes a dispatcher and Telegram command handlers move into `commands/`.

Planned command handler structure:

```text
commands/ping.sh
commands/report.sh
commands/status.sh
commands/logs.sh
commands/start_provision_arm.sh
commands/stop_provision_arm.sh
commands/restart_provision_arm.sh
```

## Testing

Basic syntax checks:

```bash
bash -n control/bot_control.sh
bash -n daemon/provision_arm.sh
bash -n tasks/report.sh
bash -n infra-tools/tg_send.sh
bash -n infra-tools/tg_receive.sh
```

Check Git safety:

```bash
git status --ignored
```

Expected ignored files include:

```text
.env
state/
logs/
```

## Operational notes

The bot can be started manually with:

```bash
nohup ./control/bot_control.sh >/dev/null 2>&1 &
```

The ARM provisioning daemon should normally be controlled through Telegram:

```text
/start provision_arm
/stop provision_arm
/restart provision_arm
```

On server reboot, cron may start `bot_control.sh`. The startup notification reminds the user to check `/status` and start `provision_arm` if necessary.
