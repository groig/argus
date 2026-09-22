# Contributing to Argus

Thanks for helping improve Argus. Keep contributions focused, include tests when behavior changes, and explain the user or operational impact in the pull request.

## Development environment

Argus is built with Elixir, Phoenix, LiveView, and PostgreSQL. To match CI, use:

- Elixir 1.19.5
- Erlang/OTP 28.3.1
- PostgreSQL 17

On Linux, install `inotify-tools` if you want Phoenix to reload the browser automatically when files change. The application still runs without it.

The application supports Elixir 1.15 and later, but using the CI versions is the best way to avoid environment-specific failures.

The default development database configuration expects PostgreSQL on `localhost:5432` with:

- username: `postgres`
- password: `postgres`
- database: `argus_dev`

For example, you can run a local PostgreSQL instance with Docker:

```bash
docker run --name argus-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=argus_dev \
  -p 5432:5432 \
  -d postgres:17
```

Restart that container in later development sessions with:

```bash
docker start argus-postgres
```

Install dependencies, create and migrate the database, seed development data, and build the assets:

```bash
mix setup
```

Then start Phoenix:

```bash
mix phx.server
```

Open `http://localhost:4000` and sign in with:

- email: `admin@argus.local`
- password: `changeme123`

Development email previews are available at `http://localhost:4000/dev/mailbox`, and LiveDashboard is available at `http://localhost:4000/dev/dashboard`.

## Making a change

1. Fork the repository and create a branch from the latest `main`.
2. Keep the change scoped to one bug, feature, or documentation improvement.
3. Add or update tests for behavior changes. Follow the testing patterns in [`docs/testing.md`](docs/testing.md).
4. Run a focused test while iterating:

   ```bash
   mix test test/path/to/relevant_test.exs
   ```

5. Run the complete quality gate before committing:

   ```bash
   mix precommit
   ```

6. Review and commit any formatting or lockfile updates produced by the quality gate. Confirm that `git status --short` is clean before pushing.

Use the existing `Req` dependency for outbound HTTP requests. Avoid adding another HTTP client unless the change has a documented requirement that `Req` cannot meet.

Generate database migrations with a descriptive snake-case name:

```bash
mix ecto.gen.migration descriptive_migration_name
```

## Pull requests

In the pull request description, include:

- what changed
- why the change is needed
- how it was tested
- screenshots for visible UI changes
- deployment or migration notes, when applicable

CI runs `mix precommit`, verifies that generated or formatted files are committed, and builds the production Docker image. A pull request is ready for review when these checks pass and its branch has no unrelated changes.

## License

By contributing to Argus, you agree that your contributions are licensed under the [GNU Affero General Public License v3.0](LICENSE).
