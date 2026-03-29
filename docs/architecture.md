# Architecture and Design

## System Shape

Argus is a Phoenix application with LiveView for the authenticated UI. Each deployment hosts one workspace. Users are invited. Teams own projects. Background delivery runs outside the ingest transaction.

The system has four main responsibilities:

1. Accept Sentry-compatible payloads.
2. Group errors into issues and keep raw events for detail views.
3. Store logs separately from issues.
4. Enforce team-based access to all projects and operational surfaces.

Those constraints keep the data model small and keep access rules consistent across the UI.

- there is one workspace per deployment
- access is invitation-only
- teams define ownership and visibility
- background delivery is asynchronous and may fail independently

## Domain Model

### Users and Access

- `User` is the global identity record.
- `Team` is the ownership boundary.
- `TeamMember` defines per-team role (`admin` or `member`).
- `Project` belongs to a team and exposes a generated DSN key.

Team ownership gives the sidebar, project pages, and admin screens the same access rule. Team members can see the team's projects. Global admins can override that when needed.

### Errors

- `ErrorEvent` is the grouped issue.
- `ErrorOccurrence` is the raw captured event.

This split matches the way people debug. The grouped issue is the thing they triage. The raw occurrence is the thing they inspect when they need the exact stack trace, request data, breadcrumbs, and locals.

### Logs

- `LogEvent` stores chronological log records.

Logs stay separate because operators usually read them by time, level, or message. Grouping them like issues would hide the sequence that makes them useful.

## Context Boundaries

- `Argus.Accounts`
  - users, invitations, password/session-adjacent account actions
- `Argus.Teams`
  - teams and team membership
- `Argus.Projects`
  - projects, grouped issues, raw occurrences, issue assignment, issue notifications
- `Argus.Ingest`
  - Sentry payload parsing and normalization
- `Argus.Logs`
  - log storage, querying, live streaming, rate limiting

Each context owns a different kind of rule. `Ingest` handles payload shape and SDK quirks. `Projects` handles grouping, lifecycle, assignment, and notifications.

## Ingestion Flow

### Error Events

1. The ingest plug validates the DSN key before controller work.
2. `Argus.Ingest` decodes the request body and normalizes Sentry payloads.
3. `Argus.Projects.upsert_issue_and_occurrence/3` creates or updates the grouped issue and inserts the raw occurrence.
4. The issue lifecycle outcome is explicit:
   - `:created`
   - `:reopened`
   - `:updated`
   - `:duplicate`
5. LiveView subscribers refresh through PubSub.
6. Notifications fire only for `:created` and `:reopened`.

Downstream behavior depends on that lifecycle result. Email and webhook delivery should run for a new issue or a reopened one, not for every update. Returning the result from the transaction is clearer than inferring it later from the stored row.

### Logs

1. Envelope `log` items are normalized in `Argus.Ingest`.
2. `Argus.Logs.create_log_event/3` enforces the rate limiter.
3. Accepted logs are inserted and broadcast to subscribed LiveViews.

The log write path is where Argus can still accept the ingest request, protect the database, and decide what to keep.

## Issue Lifecycle Rules

- New issue starts as `:unresolved`.
- Resolved issue with a new occurrence becomes `:unresolved` again.
- Ignored issue stays `:ignored` even if it appears again.
- Duplicate `event_id` does not mutate counts or status.

Resolved issues reopen because a fresh occurrence puts them back into active work. Ignored issues stay ignored because an operator already chose to suppress them.

## Notifications

Argus currently has two notification outputs:

- email
- one optional global webhook

They run asynchronously and do not block ingestion. If SMTP is down or a webhook receiver is slow, the issue should still land in the UI. The webhook is global and unsigned in v1 because the current target is an internal receiver, not a public integration surface.

Recipient rules:

- if an issue has an assignee, notify that user
- otherwise notify all confirmed members of the owning team

Assignment narrows ownership and noise. When no one is assigned, the whole team still needs to know about a new or returning problem.

## Real-Time UI Model

LiveView is used aggressively for authenticated pages:

- issue list
- issue detail
- logs list
- dashboard
- team settings
- admin panel

PubSub topics are scoped per project for issues and logs.

LiveView fits Argus because the interesting state already lives on the server: permissions, filtered lists, issue lifecycle, and subscriptions. A heavier client would add synchronization work without solving a real product problem.

## Supervision and Moving Parts

Main runtime components:

- `Argus.Repo`
- `Phoenix.PubSub`
- `Argus.Logs.RateLimiter`
- `Task.Supervisor`
- `ArgusWeb.Endpoint`

The supervision tree stays small. The rate limiter needs state, so it gets its own process. Notification work is short-lived, so a task supervisor is enough.

## Important Tradeoffs

Argus stays small on purpose. The current build favors predictable server-side behavior over breadth.

### Current Choices

- LiveView for the authenticated product UI
- asynchronous notifications without a durable job system
- team-based access rules
- separate grouped issues and raw occurrences
- a plain global webhook

### Deferred Work

- browser-level E2E harnesses such as Playwright
- durable delivery/retry queues
- per-project notification policies
- alert rules and external integrations beyond the single webhook
- distributed log-rate-limit coordination across nodes
