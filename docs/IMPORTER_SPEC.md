# Importer & Merge Specification

## Purpose

This document specifies how importers and the merge pipeline work in `stuttgart-live.de`:

- source import (`easyticket`, `eventim`)
- merge into canonical `events`
- counter semantics in `import_runs`
- status and publication behavior (`auto_published`)
- editorial implications

## Pipeline Overview

1. A source run job starts (`Importing::Easyticket::RunJob` or `Importing::Eventim::RunJob`).
2. The source importer creates an `import_runs` record (`status=running`) and processes source payloads.
3. Source rows are upserted into source-specific import tables:
   - `easyticket_import_events`
   - `eventim_import_events`
4. Images are synced into `import_event_images` (polymorphic owner = import record).
5. Import run counters are continuously persisted in `import_runs`.
6. Merge is started manually from backend (`/backend/events` -> "Import-Merge synchronisieren").
7. Merge creates its own `import_runs` record (`source_type=merge`) and syncs canonical:
   - `events`
   - `event_offers`
   - `import_event_images` (polymorphic owner = canonical event)
   - `event_change_logs`

## Database Write Map

### Source import phase

- `import_sources`: source registry (`easyticket`, `eventim`)
- `import_source_configs`: source config (location whitelist)
- `import_runs`: run status + counters
- `import_run_errors`: run/event-level import errors
- `easyticket_import_events` or `eventim_import_events`: normalized imported event data
- `import_event_images`: images linked to import event records

### Merge phase

- `import_runs` (`source_type=merge`): merge run status + counters
- `import_run_errors` (`source_type=merge`): merge failures
- `events`: canonical merged events
- `event_offers`: per-provider ticket offers per canonical event
- `import_event_images`: merged canonical image set linked to `Event`
- `event_change_logs`: audit trail (`merged_create` / `merged_update`)

## What “Upsert” Means Here

Application-level upsert pattern is used (not raw SQL `ON CONFLICT`):

- `find_or_initialize_by(...)`
- `assign_attributes(...)`
- `save!`

This is used for import rows and merged entities where applicable.

## Import Run Counters (`import_runs`)

- `fetched_count`
  - Easyticket: total dump rows fetched (`events.size`)
  - Eventim: incremented per processed feed row (streaming compatible)
- `filtered_count`
  - Count of rows that pass location whitelist matching
  - (naming is historical; semantically this is “accepted/in-scope rows”)
- `imported_count`
  - Count of rows successfully processed into import domain (includes unchanged payload path)
- `upserted_count`
  - Source runs: incremented only when importer actually performs `upsert_import_event!`
  - Unchanged payload path does **not** increment this counter
- `failed_count`
  - Count of row-level failures

### Counter meaning in Merge runs

For `source_type=merge`:

- `fetched_count = import_records_count`
- `filtered_count = 0`
- `imported_count = events_created_count + events_updated_count`
- `upserted_count = offers_upserted_count` (from `event_offers` sync, not event-row count)
- `failed_count = 0` on success

## Merge Decision Algorithm

### 1) Candidate selection

Merge reads only active import records from active sources:

- `EasyticketImportEvent.active` joined with active easyticket source
- `EventimImportEvent.active` joined with active eventim source

### 2) Grouping

Records are grouped by fingerprint:

- normalized `artist_name`
- normalized `venue_name`
- `concert_date`

Fingerprint format:

`normalize(artist)::normalize(venue)::YYYY-MM-DD`

### 3) Provider priority ordering

Within each group, records are sorted by:

1. provider priority rank (lower = higher priority)
2. `source`
3. `external_event_id`

Current intended priority order:

1. `easyticket`
2. `eventim`
3. `reservix` (for future support)

Configured priorities in `provider_priorities` override fallback priorities.

### 4) Canonical event upsert target

Canonical event lookup key is `events.source_fingerprint`.

- If found: update existing event
- If missing: create new event

### 5) Field resolution

For imported create defaults, the first non-blank value from the ordered provider list wins:

- `title`
- `artist_name`
- `city`
- `venue`
- `promoter_id`
- `promoter_name`

Also set:

- `start_at` (derived from `concert_date`, 20:00 local time)
- `primary_source` (source of highest-priority record in group)
- `source_snapshot` (full source payload snapshot)

### 6) Offers sync (`event_offers`)

Offers are built per source record and keyed by `[source, source_event_id]`.

- existing offer with key => update
- missing offer with key => insert
- stale existing offers not present in current source set => delete

This keeps ticket providers in sync with current imports.

### 7) Image sync

Image candidates from all source records are merged and deduplicated by key:

- `[source, image_type, image_url]`

Then canonical `Event` images are synced:

- insert/update changed candidates
- delete stale images no longer present

## Status Decision Rules in Merge

Status is decided by `apply_status_rules`:

1. If `status == rejected`: do nothing (protected)
2. If `status == published` and `auto_published == false`: do nothing (manually published protection)
3. Else automatic decision:
   - if `completeness.ready_for_publish?` and at least one image exists:
     - `status = published`
     - `auto_published = true`
     - `published_at ||= Time.current`
   - otherwise:
     - `status = needs_review`
     - `auto_published = false`
     - `published_at = nil` when no manual publisher exists

### Completeness gates

Blocking completeness requirements include:

- title
- artist
- start_at
- venue
- city
- image present
- ticket URL present (non-sold-out offer)

If any blocking requirement is missing, `ready_for_publish?` is false.

## `auto_published` Semantics

`auto_published` distinguishes whether current publication state is controlled by automation or manually set by editors.

- `true`: merge may continue to manage publication status
- `false`: manually published events are protected from merge status overrides

Where it is set:

- Merge sets `true` when auto-publish conditions pass
- Merge sets `false` when conditions fail
- Manual publish/unpublish and status-changing controller actions set `false`
- Default on `events` table is `false`

## Editorial Implications

### Merge-owned fields

These are merge-controlled and may be overwritten on the next merge:

- `title`
- `artist_name`
- `city`
- `venue`
- `start_at`
- `primary_source`
- `source_snapshot`
- status (subject to protection rules above)

### Create-only imported defaults

These are populated from imports when a canonical event is first created and are not overwritten on later merges:

- `promoter_id`
- `promoter_name`

`promoter_name` is currently sourced only from Reservix via `publicOrganizerName`. Eventim and Easyticket do not provide a reliable readable organizer name in the current raw payload shape.

### Editor-owned fields

These are not set by merge and remain editorial:

- `event_info`
- `editor_notes`
- `badge_text`
- `youtube_url`

### Fingerprint behavior

- Manual edits to `artist_name`/`venue` do **not** automatically recalculate `source_fingerprint`.
- A new canonical event is created only if merge computes a fingerprint that does not match an existing `events.source_fingerprint`.

## UI/UX Policy for Backend Editor

To avoid confusion with merge overwrites, merge-owned input fields are intentionally read-only in backend editor UI:

- artist
- title
- start
- city
- venue

Read-only styling is color-differentiated in editor CSS for clear visual recognition.

## Error Handling & Recovery Notes

- Import row failures are captured in `import_run_errors` and increment `failed_count`.
- Stale running runs are auto-failed/canceled based on stale and heartbeat thresholds.
- Merge failures create `import_run_errors` with `source_type=merge` and fail the merge run.

## Operational Notes

- If `provider_priorities` rows exist, they override fallback priority map.
- Ensure seeds reflect desired ranking in each environment.
- `import_runs.upserted_count` in backend list reflects different semantics:
  - source runs: import event upserts
  - merge runs: upserted offers
