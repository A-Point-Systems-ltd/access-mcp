---
name: access-database
description: Work with Microsoft Access databases via the Access-MCP server. Use when the user mentions Access, .accdb, .mdb, VBA, or Access forms/queries/tables.
---

# Microsoft Access Database Skill

You have access to a Microsoft Access database via the Access-MCP server. The MCP tools are prefixed with the server name configured by the user.

## Key Principles

1. **Always open the database first** — call `Session_OpenDatabase` before any other operation
2. **Explore before modifying** — read schema and VBA before making changes
3. **Use parameterized queries** — never concatenate user values into SQL strings
4. **Back up VBA before rewriting** — read the current code, confirm the change with the user, then write

## Typical Workflow

```
1. Session_OpenDatabase("C:\path\to\database.accdb")
2. Object_List()                    → see what's in the database
3. Schema_Tables()                  → understand table structure
4. Schema_Relationships()           → understand how tables connect
5. SQL_Select("SELECT ...")         → query data
6. VBA_Read("ModuleName")          → read VBA code
7. VBA_Updates("ModuleName", code)  → write updated VBA
8. Session_CloseDatabase()          → clean up when done
```

## Access SQL Dialect Notes

- Use `*` not `%` for wildcards in LIKE: `WHERE Name LIKE '*smith*'`
- Date literals use `#`: `WHERE OrderDate > #2024-01-01#`
- Boolean values are `True`/`False` or `-1`/`0`
- Text comparison is case-insensitive by default
- Use `IIf()` not `IF()` in queries
- `TOP N` goes after SELECT: `SELECT TOP 10 * FROM Orders`
- No `LIMIT` clause — use `TOP` instead
- Crosstab queries use `TRANSFORM ... PIVOT`

## VBA Best Practices

- Access VBA uses `Me.ControlName` to reference form controls
- `DoCmd` is the primary object for Access actions (open forms, run queries, etc.)
- Error handling: `On Error GoTo ErrHandler` pattern
- Always use `Option Explicit` at the top of modules
- `CurrentDb` returns the current database object
- `DLookup`, `DCount`, `DSum` are domain aggregate functions specific to Access

## Common Tasks

- **Schema exploration**: Start with `Object_List` then drill into specific object types
- **Data analysis**: Use `SQL_Select` with JET SQL syntax
- **VBA refactoring**: Read with `VBA_Read`, propose changes, write with `VBA_Updates`
- **Form inspection**: Use `Form_List` and `Form_Read` to understand UI structure
- **Migration prep**: Map schema with `Schema_Tables` and `Schema_Relationships`
