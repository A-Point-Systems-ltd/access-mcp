---
name: access-modernization-plan
description: Assess a Microsoft Access application and draft a modernization/migration plan — what can move to SQL Server or the web, what should stay, effort and risk per component. Use when the user asks about migrating off Access, scaling beyond it, or what a rewrite would take.
---

# Access modernization plan

Turn a live Access application into a concrete, staged modernization
assessment. Read-only: this skill analyzes and plans; it changes nothing.

## Procedure

1. **Inventory first.** Run the `access-inspect-db` flow (or reuse its output
   if fresh): objects, sizes, row counts, VBA modules.
2. **Classify the application shape.**
   - *Data-only* (tables/queries, little VBA) → strongest SQL Server
     migration candidate.
   - *Forms app* (heavy forms + VBA events) → UI rewrite is the real cost;
     data layer can still move first.
   - *Report factory* (reports + queries) → BI-tool candidates.
   - *Integration hub* (VBA that imports/exports, talks to Excel/Outlook) →
     map every external touchpoint before anything moves.
3. **Data layer assessment.**
   - Which tables are shared vs. local scratch; concurrent-user pressure.
   - Access-specific field types (Attachment, MultiValue, OLE) that need
     redesign in SQL Server.
   - Referential integrity actually enforced vs. assumed in code.
4. **Logic assessment.** Per VBA module (`VBA_Read`): what it automates, what
   it would map to (stored procedure, service, scheduled job, nothing).
   Count lines as an effort proxy; flag dead code.
5. **Staged plan.** Draft phases that each leave a working system:
   1. Hygiene (from `access-health-report` findings) — PKs, indexes, compact.
   2. **Split/upsize data** to SQL Server, keep Access front-end via linked
      tables (AccessMCP works with linked SQL tables — dynaset + SeeChanges).
   3. Rebuild the highest-value workflows outside Access.
   4. Retire components as their replacements prove out.
6. **Effort & risk table.** Per component: size, complexity (S/M/L), risk,
   dependencies, phase.

## Output

A plan document, in the user's language: application profile → component
inventory with classification → staged roadmap → effort/risk table → open
questions for the business owner. Be explicit about what **stays in Access**
— a full rewrite is rarely phase 1, and saying so builds trust.

## Rules

- Read-only tools; no schema changes, no data movement in this skill.
- Ground every effort estimate in evidence you actually collected (module
  sizes, table counts) — no generic estimates.
- Where the answer depends on business context (user counts, uptime needs,
  licensing), ask — do not assume.
