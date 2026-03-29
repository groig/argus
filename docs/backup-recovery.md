# Backup and Recovery Playbook

## What You Need to Preserve

Argus keeps its durable state in PostgreSQL.

That database includes:

- users and invitations
- teams and team membership
- projects and DSN keys
- grouped issues
- raw occurrences
- log events
- minidump blobs stored on occurrences
- auth tokens and session-related records

You also need a separate record of production secrets and deploy settings:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `PORT`
- `POOL_SIZE`
- `ARGUS_ISSUE_WEBHOOK_URL`
- mailer provider credentials and adapter config
- reverse-proxy and TLS configuration
- the release version or container image tag currently in production

Do not treat the database backup as a substitute for secret management. Keep those inventories separate.

## What Can Be Rebuilt

These do not need to be backed up:

- compiled static assets
- the release artifact itself, if you can rebuild from source or image
- local Swoosh preview state

## Recommended Backup Policy

Use PostgreSQL-native backups. Pick one of these models:

- daily logical backups with `pg_dump` plus tested restore drills
- base backups plus WAL archiving if you need point-in-time recovery

At minimum:

- run a daily logical backup
- keep multiple restore points
- test restores on a schedule

If Argus holds high-volume logs or large minidumps, plan storage and retention accordingly. Backup time and restore time will grow with the database.

## Example Logical Backup

Create a logical backup:

```bash
pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file "argus-$(date +%F-%H%M%S).dump" \
  "$DATABASE_URL"
```

Verify the dump is readable:

```bash
pg_restore --list "argus-2026-03-29-010000.dump" >/dev/null
```

## Restore Drill

Run restore drills on a scratch database, not on production.

Create the scratch database, then restore:

```bash
createdb argus_restore

pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --dbname argus_restore \
  "argus-2026-03-29-010000.dump"
```

After the restore:

1. Start Argus against the restored database in an isolated environment.
2. Log in as an existing admin user.
3. Open a project issues page.
4. Open a project logs page.
5. Confirm a known issue and a known log are present.

If the restored database will run on a newer Argus release than the source system, run migrations after the restore and before accepting traffic:

```bash
bin/argus eval "Argus.Release.migrate()"
```

## Recovery Scenarios

### Single Table or Row Mistake

If data loss is narrow and you have WAL archiving or another point-in-time method, prefer a point-in-time restore into a scratch database first. Extract the missing rows there, then decide whether to:

- repair data manually
- run a targeted SQL copy
- restore the whole production database to an earlier point

### Full Database Loss

1. Provision a fresh PostgreSQL instance.
2. Restore the latest acceptable backup.
3. Deploy the Argus release.
4. Set the production environment variables and secrets.
5. Run `bin/argus eval "Argus.Release.migrate()"`.
6. Start Argus.
7. Run the smoke checks from the deployment guide.

If you use WAL archiving, restore to the target recovery point before starting the app.

### Host Loss

If the app host is lost but the database is intact:

1. Provision a new host.
2. Deploy the same or newer Argus release.
3. Restore the environment variables and proxy config.
4. Start the app.
5. Run the smoke checks.

### Admin Access Lost

If the database is intact but you lost global-admin access, use one-off release eval commands. In Docker, run the same commands in a temporary container and replace `bin/argus` with `/app/bin/argus`.

Promote an existing user:

```bash
bin/argus eval '
Application.ensure_all_started(:argus)

user =
  Argus.Accounts.get_user_by_email("ops@example.com") ||
    raise "user not found"

{:ok, user} = Argus.Accounts.update_user_role(user, :admin)
IO.puts("Promoted #{user.email}")
'
```

Create a new admin:

```bash
bin/argus eval '
Application.ensure_all_started(:argus)

{:ok, user} =
  Argus.Accounts.create_user(%{
    email: "ops@example.com",
    name: "Ops Admin",
    role: :admin,
    password: "replace-this-password",
    password_confirmation: "replace-this-password",
    confirmed: true
  })

IO.puts("Created #{user.email}")
'
```

Do not run the demo seeds in production to regain access.

## Recovery Validation

After any real recovery:

1. Confirm `/login` loads.
2. Confirm an admin can log in.
3. Confirm projects appear in the sidebar.
4. Confirm one issue detail page renders.
5. Confirm one log detail page renders.
6. Send one test event through a project DSN.
7. Confirm the event appears in the UI.
8. If email is enabled, send an invitation.
9. If the webhook is enabled, confirm a webhook `POST`.

## Recovery Objectives

Argus does not define built-in RPO or RTO targets. Set those targets at the deployment level.

Your real recovery objectives will depend on:

- PostgreSQL backup cadence
- WAL retention policy, if any
- database size
- network reachability to SMTP or webhook targets
- how quickly you can redeploy the release and restore secrets
