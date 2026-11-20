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

Project settings can define an issue webhook URL and JSON body template.

If set, Argus will `POST` the rendered JSON body for:

- new issues
- reappearing resolved issues

If unset for a project, webhook delivery is disabled for that project and email notifications continue as usual.

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

## User Management

Global admins manage everyone in the workspace from **Admin → Users**. None of these flows need email. See [Running without email](deployment.md#running-without-email) for how they behave when SMTP is off.

### Adding users

**Add user** offers two ways to give someone access:

- **Invitation link**: creates a pending account and an invitation link that is valid for 72 hours. The person opens it and chooses their own password. If email is configured, Argus also emails the link. Either way, the dialog shows the link with a copy button and says whether the email went out.
- **Set a password**: creates an active account with the password you enter. The person can log in right away. Share the password with them over a secure channel. They can change it later under **Settings**.

Both options take a global role (`member` or `admin`) and an optional team with a team role. The user and the team membership are created together: if the team doesn't exist, nothing is created.

### Editing users

**Edit user** opens a dialog that scrolls within the window. Close it with the × button, the **Close** button, or Escape. Pressing Escape while typing in a field only leaves the field, so unsaved changes aren't lost. It has these sections:

- **Profile**: name, email, and global role. Nothing changes until you click **Save changes**. You can edit your own name and email, but not your own role. Changing someone's role disconnects their open pages so the new role applies right away. An admin who is demoted while the admin panel is open is sent away on their next action.
- **Activate with a password** (pending users) or **Reset password** (active users): sets the password directly. Activating closes the user's open invitation. In both cases Argus deletes every token the user has and disconnects their open pages, and old invitation or reset links stop working. If the user changes state while the dialog is open, for example by accepting their invitation, Argus refuses the change instead of overwriting the password they just chose. You can't reset your own password here; use **Settings**.
- **Invitation link** (pending users only): the current link with a copy button, plus **Generate new link**, which replaces the old link and emails the new one when email is configured.
- **Team memberships** and **Add to team**: change team roles, remove the user from a team, or add them to another one.
- **Danger zone**: delete the user together with their invitations, sessions, and team memberships. You can't delete yourself.

Invitation links are bound to the email address they were issued for. Changing a pending user's email invalidates their current link, so generate a new one afterwards.

### Recovering access

- A user forgot their password: reset it from **Edit user**. If email is configured, they can also use **Forgot your password?** on the login page.
- An invitation expired: open **Edit user** and click **Generate new link**, or activate the account with a password.
- The only admin is locked out: reset their password from the release console with `rpc`, which runs on the live node. This deletes the account's sessions and disconnects pages that are already open:

  ```bash
  bin/argus rpc '
  user = Argus.Accounts.get_user_by_email("admin@example.com")

  {:ok, {_user, expired_tokens}} =
    Argus.Accounts.reset_user_password(user, %{
      password: "replace-this-password",
      password_confirmation: "replace-this-password"
    })

  ArgusWeb.UserAuth.disconnect_sessions(expired_tokens)
  '
  ```

  `reset_user_password/2` sets the password but doesn't activate a pending account. To activate one, call `Argus.Accounts.admin_set_user_password/3` instead, passing another admin's scope (`Argus.Accounts.Scope.for_user(other_admin)`) as the first argument.

  To create a new admin instead, follow the first-admin steps in the [deployment guide](deployment.md).

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

Triggered for issue lifecycle and user action events:

- new issues
- resolved issues that reappear
- assignment and unassignment changes
- manual resolve, ignore, and reopen actions

Payload includes:

- event type
- issue summary
- project and team identifiers
- assignee data, if any
- actor and target user data for user actions, if any
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

- the project has a webhook URL and valid JSON body template in project settings
- new/reappearing issues and manual issue actions trigger the webhook
- repeated SDK occurrences for existing unresolved/ignored issues do not trigger webhook delivery

### Team member removed but still appears assigned

The assignment cleanup happens when the membership removal path runs through Argus. If assignments look stale in the UI, refresh the issue page to confirm the broadcast has been received.
