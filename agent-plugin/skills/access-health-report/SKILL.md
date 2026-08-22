---
name: access-health-report
description: Run a structured health check on a Microsoft Access database — integrity risks, design smells, performance hazards, maintainability debt — and produce a prioritized findings report. Use when the user asks whether a database is "okay", why it is slow or fragile, or for an audit before changes or migration.
---

# Access database health report

A read-only audit. Findings are ranked by risk; every finding names the
evidence (object, field, query) it came from. This skill never modifies the
database.

## Procedure

1. **Session.** `Session_OpenDatabase` (ask for the path if not given);
   `Session_GetDatabaseInfo` for format/size. Prefer `--read-only` sessions
   when the user offers the choice.
2. **Structural integrity.**
   - Tables without primary keys (`Object_Get` per table).
   - Fields typed as text that hold numbers/dates (sample with `Query_Read`
     `SELECT TOP 20 ...`).
   - Missing indexes on fields used by query joins/criteria (cross-reference
     each query's SQL from `Object_Get` against table indexes).
   - Broken or stale linked tables (a `SELECT COUNT(*)` that errors).
3. **Risky logic.**
   - Action queries (UPDATE/DELETE/APPEND) and what runs them.
   - Macros — especially AutoExec — and event-bound VBA (`VBA_Read`); note
     code that writes to tables or shells out.
   - Hard-coded paths, connection strings or credentials patterns in VBA —
     report the location, **never quote a credential value**.
4. **Size & performance signals.**
   - Row counts of the biggest tables (`Query_Read` COUNT).
   - File size vs. content (a bloated file suggests compact/repair is due).
   - Queries with SELECT *, cartesian joins, or stacked subqueries.
5. **Maintainability.**
   - Duplicate/near-duplicate queries; unused forms/reports (no references
     from other objects' record sources — best effort).
   - VBA compile health if available via `System_Read` diagnostics.

## Output — the report

Ordered by severity, in the user's language:

| # | Severity | Finding | Evidence | Suggested action |
|---|---|---|---|---|

Severities: **Critical** (data loss/corruption risk now) · **High** (breaks
under normal use) · **Medium** (performance/fragility) · **Low** (hygiene).

Close with a short "next steps" list: what to fix first, what needs a human
decision, and whether a compact/repair or a deeper migration review
(see `access-modernization-plan`) is warranted.

## Rules

- Read-only tools throughout; if the user asks you to also fix findings, that
  is a new task with write tools — confirm scope explicitly first.
- Never dump table data into the report; sample only what proves a finding.
- If the database is in production, recommend running against a copy.
