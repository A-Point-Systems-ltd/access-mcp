---
name: access-inspect-db
description: Open a Microsoft Access database and map it — tables, queries, forms, reports, relationships, VBA modules — before doing any other work on it. Use whenever the user points at an .accdb/.mdb file, asks "what's in this database", or before planning changes to one.
---

# Inspect an Access database

Produce a fast, structured map of an Access database using AccessMCP's read
tools only. This skill never writes.

## Steps

1. **Open a session.** Call `Session_OpenDatabase` with the absolute path the
   user gave. If they gave none, ask for it — do not guess paths. Keep the
   returned `sessionId` for every later call. If the tool reports a sign-in
   requirement, tell the user to run `access_login` first (free account, ~20
   seconds in the browser).
2. **Database facts.** `Session_GetDatabaseInfo` — format, size, path, whether
   it is opened read-only.
3. **Enumerate objects.** `Object_List` once per type: `table`, `query`,
   `form`, `report`, `macro`, `module`. Note counts per type.
4. **Tables in depth.** For each table (or the ones the user cares about):
   `Object_Get` for fields, types, sizes, indexes and primary keys. Flag
   tables with no primary key, linked tables (note their connect string
   source, but never print credentials), and suspiciously wide tables.
5. **Queries.** `Object_Get` per query for its SQL. Classify: SELECT / action
   (UPDATE, DELETE, APPEND, MAKE-TABLE) / crosstab / pass-through.
6. **Row counts (sampling).** `Query_Read` with `SELECT COUNT(*) FROM [table]`
   for the main tables. Skip linked tables that fail — note the failure
   instead of retrying.
7. **VBA overview.** `VBA_Read` to list modules and per-module line counts.
   Do not paste whole modules into the report; name them and summarize.
8. **Close politely.** If you opened the session just for this inspection,
   `Session_CloseDatabase` at the end — unless the user is continuing to work.

## Report format

Return a compact report, in the user's language:

- **Header:** file, format, size, Access version, read-only?
- **Inventory table:** object type → count.
- **Tables:** name · rows · PK? · linked? · notable fields/indexes.
- **Queries:** name · kind · one-line purpose (from its SQL).
- **VBA:** modules and what each appears to do.
- **Flags:** anything that needs attention — missing PKs, action queries,
  broken linked tables, AutoExec macro present (AccessMCP already bypasses it
  on open), ADP limitations.

## Rules

- Read tools only: `Session_*` (open/info/close), `Object_List/Get/GetProperties`,
  `Query_Read`, `VBA_Read`, `System_Read`. No `Object_Create/Update/Delete`,
  no `Query_Execute`, no `Data_Transfer`.
- One database at a time; reuse the session, never open the same file twice.
- Large databases: inventory first, then go deep only where the user directs.
