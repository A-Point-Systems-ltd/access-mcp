# Directory Compliance Preflight — run BEFORE any external submission

Source of truth: product repo `docs/plugin-platforms-development-plan.md` §5.
Every box checked (or explicitly waived, with a name and a date) before a
submission goes out to any directory. CI enforces the automatable rows.

## Eligibility gates — before investing in submission assets

- [ ] **Anthropic Plugin Directory:** open plugin + proprietary local binary —
      confirmed eligible? (their checklist requires open source; ours is an
      open manifest/bootstrap over a closed exe — ask first)
- [ ] **Anthropic Connectors Directory (mcpb):** open-source requirement vs.
      closed exe — confirmed eligible?
- [ ] **Cursor Marketplace:** open-source policy vs. proprietary downloaded
      binary — answered? (plan decision ה-8)
- [ ] **OpenAI Plugin Directory:** per D5 spike verdict.

> Self-distribution (GitHub Releases, our own marketplace, `.mcpb` from the
> site) is **GO** regardless of every answer above.

## Tool Surface Directory Audit (before annotations, not after)

- [ ] Per tool (all 27): read-only? writes? deletes? behavior changes by
      action/args?
- [ ] Mixed read/write tools identified; each split, or covered by a
      directory-safe reduced tool surface — an annotation on a mixed tool is
      not sufficient
- [ ] Then: `title` + `readOnlyHint`/`destructiveHint` correct on every tool

## Assets & requirements

- [ ] Privacy Policy URL live on the site (`https://access-mcp.ai/privacy`)
- [ ] `privacy_policies[]` present in the mcpb `manifest.json` + Privacy
      section in the dist README
- [ ] Support URL live + monitored mailbox (product debt #28)
- [ ] `LICENSE` in this repo is the final EULA text (NOT the placeholder —
      CI blocks releases while the placeholder marker is present)
- [ ] Allowlist of external URLs the tools open (upgrade_url, docs)
- [ ] Icon/assets at every required size
- [ ] Windows-only compatibility declared in every manifest
      (`win32` / `supported_os`)
- [ ] Clean install instructions per client + public documentation
- [ ] 3+ working usage examples (submission requirement)
- [ ] Reviewer demo path: trial account + sample database + instructions
- [ ] exe signed (EV) — precondition for submissions, not just UX
