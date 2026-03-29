# Deployment Guide

## Deployment Model

Argus is easiest to run as a single Phoenix node behind a reverse proxy, backed by PostgreSQL.

The repository includes a multi-stage `Dockerfile` that builds the Phoenix release and runs it in a slim Debian image. If you already deploy with containers, use that image as the production artifact and keep PostgreSQL outside the app container.

A production deployment needs:

- one Argus release or container
- one PostgreSQL database
- TLS termination at a reverse proxy or load balancer
- a real Swoosh adapter if you want email delivery

Argus keeps durable application data in PostgreSQL. There is no user-uploaded file store to mount or replicate. Raw event payloads, logs, and minidump blobs are stored in the database.

Multi-node deployments are possible, but they add moving parts without changing the product model. The log rate limiter is node-local. Notification delivery is asynchronous and local to the node that handled the event.

## Required Runtime Environment

Set these variables before starting the release or container:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `PORT`

Optional variables:

- `POOL_SIZE`
- `ECTO_IPV6`
- `ARGUS_ISSUE_WEBHOOK_URL`
- `DNS_CLUSTER_QUERY`

`PHX_HOST` should match the public host users and SDKs reach. Project DSNs use that host.

Set `PHX_SERVER=true` when you start the release directly with `bin/argus start` or `bin/argus daemon`. The provided container command uses `/app/bin/server`, which sets `PHX_SERVER=true` for you.

## Email in Production

The repo ships with the local Swoosh adapter for development and the test adapter for tests. Production email needs a real adapter configured before you rely on invitation or issue emails.

Keep two facts in mind:

- API-based adapters work well with the existing `Req` client setup in `config/prod.exs`
- SMTP is configured at runtime through `ARGUS_SMTP_*` variables

For SMTP delivery, set:

- `ARGUS_SMTP_RELAY`
- `ARGUS_SMTP_PORT` with a common default of `587`
- `ARGUS_SMTP_USERNAME`
- `ARGUS_SMTP_PASSWORD`
- `ARGUS_SMTP_TLS` as `always`, `if_available`, or `never`
- `ARGUS_SMTP_SSL` as `true` or `false`
- `ARGUS_SMTP_AUTH` as `always`, `if_available`, or `never`
- `ARGUS_SMTP_HOSTNAME` if your relay expects a stable EHLO/HELO name
- `ARGUS_SMTP_FROM_NAME`
- `ARGUS_SMTP_FROM_ADDRESS`

Argus verifies the SMTP server certificate and hostname. Keep `ARGUS_SMTP_RELAY`
set to the relay hostname, not an IP address. For Microsoft 365, use
`smtp.office365.com` on port `587` with `ARGUS_SMTP_TLS=always` and
`ARGUS_SMTP_SSL=false`.

Example:

```dotenv
ARGUS_SMTP_RELAY=smtp.example.com
ARGUS_SMTP_PORT=587
ARGUS_SMTP_USERNAME=mailer@example.com
ARGUS_SMTP_PASSWORD=replace-me
ARGUS_SMTP_TLS=always
ARGUS_SMTP_SSL=false
ARGUS_SMTP_AUTH=always
ARGUS_SMTP_HOSTNAME=argus.example.com
ARGUS_SMTP_FROM_NAME=Argus
ARGUS_SMTP_FROM_ADDRESS=alerts@example.com
```

If you are not ready to send email yet, leave `ARGUS_SMTP_RELAY` unset and use the webhook path for issue notifications.

To test SMTP from a running release, use `rpc` on the live node rather than a
one-off `eval` container. `eval` does not boot the full application tree and can
fail with `:ssl_not_started` even when production delivery is configured
correctly.

```bash
/app/bin/argus rpc '
email =
  Swoosh.Email.new()
  |> Swoosh.Email.to("you@example.com")
  |> Swoosh.Email.from(Argus.Mailer.from())
  |> Swoosh.Email.subject("Argus SMTP test")
  |> Swoosh.Email.text_body("SMTP test")

IO.inspect(Argus.Mailer.deliver(email), label: "deliver_result")
'
```

## Building a Release

Build the release on a machine that matches the target OS and CPU architecture:

```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

The result is a release under `_build/prod/rel/argus`.

## Building a Docker Image

Build the image from the repository root:

```bash
docker build -t argus:0.1.0 .
```

For CI and registries, prefer an immutable tag and push it once:

```bash
docker buildx build \
  --platform linux/amd64 \
  -t ghcr.io/acme/argus:0.1.0 \
  -t ghcr.io/acme/argus:sha-$(git rev-parse --short HEAD) \
  --push .
```

Build the image once, then promote that same image between staging and production. Change configuration with environment variables and secrets, not by rebuilding per environment.

## First Production Bootstrap

Do not run `priv/repo/seeds.exs` in production. The seeds create demo data.

For the first deploy:

1. Create the database.
2. Run the migrations.
3. Start the release.
4. Create the first admin user.

Run migrations from the release:

```bash
bin/argus eval "Argus.Release.migrate()"
```

Create the first admin from the release:

```bash
bin/argus eval '
Application.ensure_all_started(:argus)

{:ok, user} =
  Argus.Accounts.create_user(%{
    email: "admin@example.com",
    name: "Argus Admin",
    role: :admin,
    password: "replace-this-password",
    password_confirmation: "replace-this-password",
    confirmed: true
  })

IO.puts("Created #{user.email}")
'
```

After the first admin exists, all other users should come through invitations from the UI.

## Starting the Release

Foreground:

```bash
PHX_SERVER=true bin/argus start
```

Daemonized:

```bash
PHX_SERVER=true bin/argus daemon
```

Graceful stop:

```bash
bin/argus stop
```

## Docker Runtime Example

For a small self-hosted deployment, build the image once, run migrations in a one-off container, then start the app container behind a reverse proxy.

The example below assumes PostgreSQL is reachable as `db` on a Docker network named `argus`. If you use a managed database instead, point `DATABASE_URL` at that host and drop the custom Docker network flags.

Example `.env.production`:

```dotenv
DATABASE_URL=ecto://argus:change-me@db/argus
SECRET_KEY_BASE=replace-with-output-from-mix-phx-gen-secret
PHX_HOST=argus.example.com
PORT=4000
POOL_SIZE=10
```

Create the network once if you are wiring the app and database together with plain Docker:

```bash
docker network create argus
```

Run the first migration:

```bash
docker run --rm \
  --env-file .env.production \
  --network argus \
  argus:0.1.0 \
  /app/bin/migrate
```

Create the first admin:

```bash
docker run --rm \
  --env-file .env.production \
  --network argus \
  argus:0.1.0 \
  /app/bin/argus eval '
Application.ensure_all_started(:argus)

{:ok, user} =
  Argus.Accounts.create_user(%{
    email: "admin@example.com",
    name: "Argus Admin",
    role: :admin,
    password: "replace-this-password",
    password_confirmation: "replace-this-password",
    confirmed: true
  })

IO.puts("Created #{user.email}")
'
```

Start the app container:

```bash
docker run -d \
  --name argus \
  --restart unless-stopped \
  --env-file .env.production \
  --network argus \
  -p 4000:4000 \
  argus:0.1.0
```

If your reverse proxy runs on the same Docker network, omit `-p 4000:4000` and publish only the proxy.

## Example Docker Compose

For a single-host deployment, a small Compose stack is enough:

```yaml
services:
  db:
    image: postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_DB: argus
      POSTGRES_USER: argus
      POSTGRES_PASSWORD: change-me
    volumes:
      - argus-db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U argus -d argus"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: ghcr.io/acme/argus:0.1.0
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - .env.production
    ports:
      - "4000:4000"

volumes:
  argus-db:
```

With that layout, set `DATABASE_URL=ecto://argus:change-me@db/argus` in `.env.production`, then use:

```bash
docker compose run --rm app /app/bin/migrate
docker compose up -d app
```

## Using the Image in Production

Treat the image as the release artifact. Do not rebuild it on the production host for each deploy.

A typical Compose-based rollout is:

```bash
docker compose pull app
docker compose run --rm app /app/bin/migrate
docker compose up -d app
```

With plain Docker, the equivalent flow is:

```bash
docker pull ghcr.io/acme/argus:0.1.0
docker run --rm --env-file .env.production --network argus ghcr.io/acme/argus:0.1.0 /app/bin/migrate
docker rm -f argus
docker run -d --name argus --restart unless-stopped --env-file .env.production --network argus -p 4000:4000 ghcr.io/acme/argus:0.1.0
```

The app container is stateless. Persist PostgreSQL, keep secrets outside the image, and promote the same image digest through every environment.

## Reverse Proxy Notes

Production config expects TLS to terminate before Phoenix. The proxy must set `X-Forwarded-Proto` so `force_ssl` behaves correctly.

The simplest layout is:

- proxy listens on 443
- proxy forwards to Argus on the internal `PORT`
- Argus binds on all interfaces inside the deployment network

## Standard Release Deploy Procedure

1. Build a new release.
2. Take or verify a recent database backup.
3. Copy the release to the target host.
4. Stop the old node or take it out of rotation.
5. Run `bin/argus eval "Argus.Release.migrate()"`.
6. Start the new release.
7. Run the smoke checks below.

Argus has no built-in job queue, so there is no worker drain step. The main risk during deploy is interrupting active LiveView sessions or losing in-flight notification tasks.

If you deploy with containers instead of a copied release, use the image rollout flow from the Docker section above.

## Smoke Checks

Run these checks after each deploy:

1. Load `/login` through the public URL.
2. Log in as an admin user.
3. Open a project issues page.
4. Open a project logs page.
5. Send a test event through the project DSN.
6. Confirm the issue or log appears in the UI.
7. If email is enabled, send an invitation and confirm delivery.
8. If the webhook is enabled, trigger a new issue and confirm a webhook `POST`.

## Health Checks

Argus does not ship with a dedicated `/health` endpoint.

For now, use one of these:

- a TCP check on the app port
- a proxy-level check against `GET /login`
- an external synthetic check that loads `/login` and verifies a `200`

If you need a database-aware health check, add a dedicated endpoint before putting that requirement on a load balancer.
