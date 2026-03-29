# Operations Guide

See also:

- [Deployment Guide](deployment.md)
- [Production Runbook](production.md)
- [Backup and Recovery Playbook](backup-recovery.md)

## Local Development

Install, migrate, seed, and build assets:

```bash
mix setup
```

Start the application:

```bash
mix phx.server
```

Useful local URLs:

- app: `http://localhost:4000`
- dev mailbox preview: `http://localhost:4000/dev/mailbox`
- live dashboard: `http://localhost:4000/dev/dashboard`

## Default Credentials

Seeds create:

- `admin@argus.local`
- `changeme123`

This is for local development only.

## Runtime Configuration

### Core Phoenix / Repo

- `PORT`
- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `PHX_SERVER`
- `POOL_SIZE`
- `ECTO_IPV6`

### Issue Notifications

- `ARGUS_ISSUE_WEBHOOK_URL`

If set, Argus will `POST` JSON for:

- new issues
- reappearing resolved issues

If unset, webhook delivery is disabled and email notifications continue as usual.

### Log Rate Limiting

Configured via application config:

```elixir
config :argus, Argus.Logs.RateLimiter,
  enabled: true,
  max_logs: 1_000,
  window_seconds: 60
```

Behavior:

- over-limit logs are dropped
- one synthetic warning log is emitted when suppression starts
- enforcement is per project and node-local

This setting is regular application config today. Change it through a new build and deploy.

## Ingestion Endpoints

- `POST /api/:project_id/store/`
- `POST /api/:project_id/envelope/`

Authentication uses the project DSN key.

DSN shape in the UI:

```text
http(s)://<dsn_key>@<host>/<project_id>
```

## Notification Behavior

### Email

Triggered for:

- new issues
- resolved issues that reappear

Recipients:

- assignee only, if assigned
- otherwise all confirmed members of the owning team

Production email depends on a real Swoosh adapter. The deployment guide covers that setup.

Email delivery runs after the issue write path. Failures are logged and do not fail ingestion.

### Webhook

Triggered for the same lifecycle events as email.

Payload includes:

- event type
- issue summary
- project and team identifiers
- assignee data, if any
- canonical issue URL

Webhook delivery is also asynchronous and non-retrying in v1.

## Operational Semantics

### Issues

- resolved issues reopen when they appear again
- ignored issues remain ignored
- duplicate `event_id` payloads are treated as duplicates and do not increment counts

### Assignment

- one assignee per issue
- assignee must be a member of the project’s team
- removing a user from a team automatically unassigns that user from the team’s issues

## Common Maintenance Commands

Reset the database:

```bash
mix ecto.reset
```

Run migrations only:

```bash
mix ecto.migrate
```

Run the full quality gate:

```bash
mix precommit
```

## Troubleshooting

### SDK sends events but nothing appears

Check:

- the DSN scheme is correct for the deployment (`http` vs `https`)
- the sender can actually reach the configured host
- the project id and DSN key match
- the payload is using supported Sentry envelope/store formats

### Python SDK logs do not appear

Argus supports Sentry log envelope items. If a client uses a payload type Argus does not yet consume, the request may still be accepted but the log will be ignored.

### Webhook receiver sees nothing

Check:

- `ARGUS_ISSUE_WEBHOOK_URL` is set in the running environment
- only new/reappearing issues trigger the webhook
- existing unresolved/ignored issue updates do not trigger webhook delivery

### Team member removed but still appears assigned

The assignment cleanup happens when the membership removal path runs through Argus. If assignments look stale in the UI, refresh the issue page to confirm the broadcast has been received.
