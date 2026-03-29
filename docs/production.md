# Production Runbook

## What to Watch

At minimum, watch these signals:

- Argus process up and accepting HTTP traffic
- PostgreSQL reachable and healthy
- HTTP 5xx rate
- database size and growth rate
- notification failures in application logs
- webhook failures in application logs

Argus stores raw occurrences, logs, and minidump blobs in PostgreSQL. Database growth is one of the main operational limits of this build.

## Logs and Metrics

Argus writes application logs through the standard Elixir logger. In production, route stdout and stderr into your log collector.

Look for these patterns:

- failed issue webhook delivery
- failed issue notification email
- log rate limit exceeded
- database connection errors
- repeated ingest decode failures

The synthetic `Log rate limit exceeded` warning means Argus has started dropping logs for a project inside the current rate-limit window.

## Daily and Weekly Checks

Daily:

- confirm the app answers `/login`
- review 5xx and database error logs
- check recent issue notifications if email or webhook delivery matters operationally

Weekly:

- review database size
- review growth in `error_occurrences` and `log_events`
- verify backup jobs completed
- restore a recent backup into a scratch database if you do not already run restore drills elsewhere

## Data Growth

Argus does not ship with built-in retention or pruning jobs.

That means:

- logs grow until you delete them
- raw occurrences grow until you delete them
- minidump blobs stay in PostgreSQL with the occurrence row

If you need retention, manage it at the database layer or add an explicit pruning job to the app.

## Notification Semantics

Issue emails and webhook calls run after the main issue write path.

Operational consequences:

- ingest success does not mean email or webhook delivery succeeded
- notification failures show up in logs, not in the UI
- a node restart can interrupt in-flight notification tasks

This behavior is acceptable for the current product scope, but it should be part of your expectations when you run the system.

## Scaling Notes

Single-node deployment is the safest operating model today.

If you run multiple nodes:

- all nodes must share the same database
- all nodes must use the same `SECRET_KEY_BASE`
- LiveView session routing should stay stable at the proxy
- log rate limiting stays node-local
- notification delivery still has no durable retry path

`DNS_CLUSTER_QUERY` is available if you want Erlang node discovery in a clustered setup.

## Configuration Changes

Some production settings are runtime environment variables. Others are application config and require a rebuild or a new release artifact.

Current examples:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, and `ARGUS_ISSUE_WEBHOOK_URL` are runtime inputs
- the log rate limiter is configured in `config/config.exs` and currently requires a new build to change
- mailer adapter choice should be treated as deployment config and reviewed before each production rollout

## Routine Operator Tasks

Use the release for these tasks:

Run migrations:

```bash
bin/argus eval "Argus.Release.migrate()"
```

If you operate Argus in Docker, run the same commands in a one-off container and replace `bin/argus` with `/app/bin/argus`. For example:

```bash
docker compose run --rm app /app/bin/migrate
```

For emergency admin promotion or creation, use the `bin/argus eval` snippets in the backup and recovery guide. This checkout currently exposes migration helpers in `Argus.Release`, not account-management helpers.

## Upgrade Checklist

Before the deploy:

1. Confirm a recent database backup exists.
2. Review schema migrations for locking risk.
3. Confirm email and webhook dependencies are reachable if you rely on them.

After the deploy:

1. Run the smoke checks from the deployment guide.
2. Confirm at least one issue page and one log page render.
3. Send one test ingest event.
4. Watch logs for migration, database, or notification errors.

## Known Gaps

Keep these limits in mind when you operate Argus:

- no dedicated health endpoint
- no built-in data retention
- no durable background job queue
- no per-project notification policies
- no cluster-wide log rate limiting
