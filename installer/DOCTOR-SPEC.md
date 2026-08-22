# `accessmcp doctor` + installer — spec

> **STATUS.** `accessmcp doctor` is **implemented** in
> `MS.Access.MCP/Diagnostics/Doctor.cs` (dispatched from `Program.Main`, before any
> MCP server is constructed). The **installer** around it is still a discovery
> spike: no bundled signed exe, no install E2E test, no signing/update channel.
> Gaps tracked in `../../ALIGNMENT-REPORT.md`.

Installer (signed; MSI/Inno vs MSIX = discovery decision):
copy exe → write Cursor config or open deeplink (user choice) → optional
Claude plugin dir install → run `accessmcp doctor`.

---

## 1. The command

```
accessmcp doctor                      human-readable, support-pasteable report
accessmcp doctor --json               machine-readable report (same checks)
accessmcp doctor --database <path>    additionally check one database file
accessmcp doctor --help
```

`--db` is accepted as a synonym for `--database`, and a bare positional argument
is treated as the database path (matching the server's CLI). `--doctor` anywhere
on the command line works as well as the `doctor` verb in first position.

**Exit code 0 when every check passes; 1 when any check FAILs.** WARN never fails
the run — not being signed in, and an unreachable control plane while signed in,
are legitimate states, not defects.

**Every FAIL carries a remedy.** This is enforced by the type: the internal
`Fail(line, remedy)` helper has no overload without a remedy. A diagnostic that
only says FAIL moved the problem, it did not diagnose it.

## 2. The never-mutates rule

Doctor is a read-only instrument, without exception:

- it never opens or writes an Access database. The `--database` check opens the
  file `FileAccess.Read` / `FileShare.ReadWrite` and reads one byte, so it
  neither modifies the file nor blocks an Access instance that already has it;
- it never executes a tool, never reserves and never commits usage;
- it **never asks for a work pass.** `POST /v1/pass` would consume one of the
  account's three machine slots, which is a mutation of account state. Doctor
  therefore constructs `ApiClient` directly and never touches `ToolGate` /
  `PassManager`;
- the only control-plane calls are `GET /healthz`, `GET /readyz` and
  `GET /v1/me`. None of them spends a credit. `GET /v1/me` may rotate the
  refresh token exactly as any ordinary call would — that is the whole cost of
  proving the stored credential still works, and it is documented rather than
  avoided;
- it never starts the MCP stdio loop, so stdout is a plain console stream.

**Output hygiene:** no token, pass or secret is ever printed. The `--json`
report never contains a resolved database path — only the argument exactly as
the user typed it, the file name, and the salted `Fingerprint.Db` hash.

## 3. The checks

| # | id | What it proves | Failure copy → remedy |
|---|----|----------------|------------------------|
| 1 | `runtime` | exe version + file version + build time, .NET runtime, OS build, process **and** OS architecture, machine fingerprint | FAIL only when the host is not Windows → "run accessmcp.exe on Windows, on the same machine as Access" |
| 2 | `access` | `Access.Application` ProgID resolves; registered version from `HKCR\Access.Application\CurVer`; `MSACCESS.EXE` located via `App Paths` (all hive/view combinations) with its file version and **PE architecture** | FAIL "the ProgID does not resolve — Microsoft Access is not installed for this Windows user" → the "Access is required; this product runs where Access runs" remedy |
| 3 | `ace-provider` | an ACE/OLEDB provider is registered **and its architecture matches this process** | FAIL "Bitness mismatch: this exe is x64, the installed ACE provider is x86 (Microsoft.ACE.OLEDB.12.0)" → install the matching redistributable, or run the accessmcp build matching Office's bitness (named explicitly when Office's architecture was detected in check 2) |
| 4 | `credentials` | DPAPI `Protect`/`Unprotect` round-trip of a random throwaway probe (CurrentUser); whether a stored refresh token exists **and decrypts** | FAIL on a broken round-trip → roaming/temporary profile, restored profile, or policy. WARN when the file exists but cannot be decrypted → sign in again |
| 5 | `control-plane` | resolved base URL (and whether `ACCESSMCP_BASE_URL` overrode it), `GET /healthz` status + latency, clock skew vs the server `Date` header, `GET /readyz` (`ready`, `missing[]`, `write_tools_enabled`) | **FAIL only when unreachable AND not signed in** (signing in is then impossible). Unreachable while signed in is a WARN — offline work is a paid feature |
| 6 | `account` | `GET /v1/me`: email, plan + status, trial days left, write availability (`plan.write_enabled` AND `server_capabilities.write_tools_enabled`), today's usage and reset | Not signed in → **WARN** with the canonical `accessmcp login` copy (`NeedsLoginException.NotSignedInMessage`), never a FAIL. FAIL only when the control plane answered `/healthz` but rejected the account call |
| 7 | `tool-policy` | the generated `ToolPolicy` loads; its count and free/paid split; the count matches the engine's `ToolDefinitions.GetAllTools()`, name for name | FAIL naming the exact drift ("missing from the policy: X", "in the policy but not listed by the engine: Y") → `node scripts/generate-policy.mjs` |
| 8 | `database` | *(only with `--database`)* exists, plausible extension, `.laccdb`/`.ldb` record-locking file, `.mcp.lock` sidecar, and readability | FAIL when missing, 0 bytes, or unopenable (exclusive lock / permissions). Lock files are WARN — shared use is normal |

The base URL is resolved by `Doctor.ResolveBaseUrl`, which `Program.Main` also
uses, so the doctor can never report an origin the server would not use
(including the release-build restriction to `*.access-mcp.ai`).

## 4. Deltas from the 2025 spike spec (and why)

The list below is the previous version of this file, item by item.

1. ~~"exe version + update channel reachable"~~ → **exe version, file version and
   build timestamp are reported; the update channel is not.** There is no update
   channel yet — no signed installer and no feed — so a check for it could only
   ever be theatre.
2. ~~"in prod builds doctor FAILS unless `readyz.ready == true` and a recorded
   live-login smoke exists for microsoft+google+github"~~ → **`/readyz` is
   reported (including `missing[]` and the `write_tools_enabled` kill switch)
   but only ever WARNs.** `/readyz` is *our* launch guard; a customer's doctor
   must not go red because our IdP configuration is incomplete — that would turn
   a support tool into a false alarm on a perfectly healthy machine. The launch
   gate stays where it belongs: the deploy smoke in the product repo's setup guide
   and the product repo's ops docs. The "recorded live-login smoke" half is not
   implementable from the client at all — no endpoint exposes it.
3. DPAPI round-trip → **implemented as specified** (random probe, CurrentUser,
   compared with `CryptographicOperations.FixedTimeEquals`, never printed).
4. "token present? → offer `access_login`" → **implemented as a WARN plus the
   canonical copy.** Doctor *tells*, it does not *offer*: launching a device
   flow from a diagnostic would be a mutation.
5. `GET /v1/me` → **implemented**, including the `server_capabilities` echo,
   trial days left and today's usage.
6. ACE/COM provider registered + bitness matches exe → **implemented**, and
   sharpened: architecture comes from the **PE header** of the registered
   `InprocServer32` DLL, not merely from which registry view it was found in, so
   a broken install that registers a 32-bit DLL in the 64-bit view is still
   named correctly.
7. ~~"sample `.laccdb` lock detection self-test"~~ → **replaced by
   `--database <path>`.** A synthetic self-test proves nothing about the file the
   user is actually stuck on; checking the real file does.
8. ~~"Cursor/Claude config detected? show which, offer to (re)write"~~ → **not
   implemented.** Writing a client config is a mutation and belongs to the
   installer, which is still a spike. Reporting alone is on the backlog.
9. "clock skew < 60s (JWT exp sanity)" → **implemented, with a wider band.**
   Measured against the `Date` header of the `/healthz` response; WARN above
   ±120s, because the number that actually matters is `PassClaims.ClockSkewSec`
   (±300s), beyond which a valid work pass is rejected locally and every paid
   session silently falls back to per-call metering.

## 5. What doctor replaces in the Windows smoke test

The pre-launch Windows smoke test (the product repo's setup guide, the last
unverified item before `WRITE_TOOLS_ENABLED=true`) was a manual click-through.
`accessmcp doctor --database <path>` now covers its environmental half in one
command: Access present, ACE bitness, DPAPI, control plane, signed-in account
with the plan and write-availability it reports, tool-policy/engine agreement,
and the target database being present and openable.

What it deliberately does **not** cover, because doctor never executes a tool:
the actual open → read → VBA round-trip through the gate on a live Access
instance. That remains a manual step — but it now starts from a machine that has
already been proven, instead of from a guess.
