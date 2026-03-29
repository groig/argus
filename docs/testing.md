# Testing Guide

## Philosophy

Argus uses a server-first testing strategy:

- unit tests for domain rules
- integration tests for HTTP and ingestion boundaries
- LiveView tests for product workflows
- smoke tests for cross-cutting end-to-end flows

Most bugs in Argus come from server-side behavior: grouping, auth, assignment, notifications, rate limiting, and LiveView state transitions. ExUnit and LiveView tests cover that surface with less flake and less setup than a browser automation stack.

## Test Layers

### Unit

Examples:

- `test/argus/projects_test.exs`
- `test/argus/logs/rate_limiter_test.exs`
- `test/argus/logs_test.exs`
- `test/argus/projects/issue_notifier_test.exs`

Focus:

- issue lifecycle
- assignment rules
- log rate limiting
- notification recipient selection
- webhook payload behavior

### Integration

Examples:

- `test/argus/accounts_test.exs`
- `test/argus_web/controllers/ingest_controller_test.exs`
- `test/argus_web/user_auth_test.exs`

Focus:

- invitation acceptance
- session behavior
- Sentry-compatible ingest
- encoding support
- DSN auth and non-retryable responses

### LiveView

Examples:

- `test/argus_web/live/issues_live/index_test.exs`
- `test/argus_web/live/issues_live/show_test.exs`
- `test/argus_web/live/logs_live/index_test.exs`
- `test/argus_web/live/logs_live/show_test.exs`
- `test/argus_web/live/admin_live/index_test.exs`
- `test/argus_web/live/team_live/settings_test.exs`

Focus:

- dashboard and navigation
- issue triage flows
- stacktrace/event inspection
- issue assignment
- logs filtering and tail mode
- admin/team management

### Smoke Flows

Example:

- `test/argus_web/e2e/workspace_smoke_test.exs`

Focus:

- invitation
- team membership
- project creation
- ingestion
- visibility of resulting issues to a real user

## Commands

Run everything:

```bash
mix test
```

Run a focused file:

```bash
mix test test/argus/projects_test.exs
```

Run the whole quality gate:

```bash
mix precommit
```

## Writing New Tests

### Prefer the smallest useful layer

- use unit tests when the rule is purely contextual or data-oriented
- use controller tests when validating request/response contracts
- use LiveView tests when behavior depends on rendered state and user interaction
- add smoke tests only for flows that cross multiple subsystems

### Assert outcomes, not implementation trivia

Good:

- issue status became `:unresolved`
- assignee changed
- webhook payload contains the expected event type
- a user can see the issue after onboarding

Less useful:

- private helper output in isolation
- internal assign names unless they are the rendered contract

### Keep fixtures explicit

Use the helpers in:

- `test/support/fixtures/accounts_fixtures.ex`
- `test/support/fixtures/workspace_fixtures.ex`

If a test needs a special lifecycle state, prefer creating that state directly in the test instead of inflating the shared fixtures with unrelated defaults.

## Browser-Level E2E

Argus does not currently ship with Playwright or Wallaby.

Most of the current risk is still on the server, not in cross-browser client code. LiveView tests already cover:

- routing
- forms
- trigger-action flows
- patches and redirects
- PubSub-driven updates

Browser automation becomes worthwhile when client-side behavior or cross-browser differences carry more risk than the server-side state machine. Argus is not there yet.

## Coverage Priorities

The most important areas to keep covered are:

1. ingestion and grouping behavior
2. invitation-only auth and session handling
3. issue lifecycle transitions
4. issue detail rendering
5. project/team/admin management flows
6. notification fanout and non-blocking behavior

If future work forces a tradeoff, protect those surfaces first.
