# Argus

Argus is a self-hosted error tracker and log ingester built with Elixir, Phoenix, and LiveView. It accepts Sentry-compatible payloads, groups errors into issues, stores raw events and logs, and exposes an internal UI for triage, project management, and access control.

Each deployment hosts one internal workspace. Admins invite users, teams own projects, LiveView powers the UI, and notification delivery runs after the main write path so ingest stays responsive.

## Screenshots

### Team overview

![Argus team overview](docs/screenshots/dashboard.png)

### Issue detail

![Argus issue detail](docs/screenshots/issue-detail.png)

### Log detail

![Argus log detail](docs/screenshots/log-detail.png)

## Quick Start

1. Install dependencies and prepare the database:

   ```bash
   mix setup
   ```

2. Start the server:

   ```bash
   mix phx.server
   ```

3. Visit `http://localhost:4000`.

## Seeded Access

`mix setup` runs the seeds and creates:

- admin email: `admin@argus.local`
- password: `changeme123`

The seed also creates:

- team: `Engineering`
- project: `My First Project`

The project DSN key is printed to stdout when the seeds run.

## Included Today

- Sentry `store` and `envelope` ingestion
- error grouping by fingerprint
- raw occurrences for event-level debugging
- separate log storage with live tail support
- users, teams, projects, invitations, and issue assignment
- email notifications and an optional webhook for new and reappearing issues

## Documentation

- [Architecture and Design](docs/architecture.md)
- [Deployment Guide](docs/deployment.md) - release and Docker/container deployment
- [Operations Guide](docs/operations.md)
- [Production Runbook](docs/production.md)
- [Backup and Recovery Playbook](docs/backup-recovery.md)
- [Testing Guide](docs/testing.md)

## Common Commands

Run the full test suite:

```bash
mix test
```

Run the full precommit gate:

```bash
mix precommit
```

Reset the database locally:

```bash
mix ecto.reset
```

Refresh the README screenshots locally:

```bash
bin/screenshots
```

## Development Notes

- Dev mail preview is available at `http://localhost:4000/dev/mailbox`
- The optional issue webhook is configured with `ARGUS_ISSUE_WEBHOOK_URL`
- Logs can be rate-limited globally through `config :argus, Argus.Logs.RateLimiter, ...`
- `bin/screenshots` uses the local `chromium` and `chromedriver` binaries and seeds a dedicated screenshot workspace instead of dropping your dev database

## Out of Scope Today

- performance monitoring
- release health
- source maps
- code snippet syntax highlighting
- alert rules and integrations beyond the single webhook

## License

See [LICENSE](LICENSE).
