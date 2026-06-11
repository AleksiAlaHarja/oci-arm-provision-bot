# TODO

## High priority

- Review and test Copilot refactor PR for splitting `control/bot_control.sh` into command handler scripts.
- Verify that all Telegram commands still work after refactor:
  - `/ping`
  - `/report`
  - `/status`
  - `/start provision_arm`
  - `/stop provision_arm`
  - `/restart provision_arm`
  - `/logs`
  - `/logs <target>`
  - `/logs <target> <lines>`
- Improve successful ARM provision notification:
  - mention the user clearly
  - include instance OCID
  - include public IP if available
  - include SSH command
  - clearly state that the target ARM server was created
- Add `/reset stats` command for resetting `state/stats.json`.

## Medium priority

- Add Telegram message length protection for `/logs`, especially `/logs all`.
- Add better success-state handling after ARM instance creation.
- Decide whether `provision_arm.sh` should stop after success or enter a post-success monitoring mode.
- Add documentation for the reboot behavior:
  - cron starts `bot_control.sh`
  - `bot_control.sh` sends startup notification
  - user checks `/status`
  - user starts `provision_arm` manually if needed

## Documentation

- Update `README.md` after Copilot refactor is merged.
- Add `docs/architecture.md`.
- Add ADR documents:
  - `docs/adr/0001-bash-based-agent.md`
  - `docs/adr/0002-telegram-command-dispatcher.md`
  - `docs/adr/0003-runtime-state-and-logs-not-committed.md`
  - `docs/adr/0004-cron-reboot-startup-instead-of-systemd.md`

## Later

- Add Docker and Docker Compose setup for the target ARM server.
- Add migration checklist from x86 watcher to ARM server.
- Add OpenClaw/Gemini/Telegram runtime setup for the target ARM server.
- Add stronger alerting when ARM provisioning succeeds.
- Consider replacing Bash with Python only if complexity grows significantly.

## Done

- Initial GitHub repository created.
- Public-safe `.gitignore` added.
- `.env.example` added.
- Secrets, logs and runtime state excluded from Git.
- `README.md` added.
- Telegram bot control implemented.
- ARM provisioning retry loop implemented.
- Daily report implemented at 07:00 Europe/Helsinki time.
- `/logs` command implemented.
- Stale PID correction implemented in `/status`.
- Project directory renamed to `oci-arm-provision-bot`.
- Active scripts updated to use relative `BASE_DIR`.
