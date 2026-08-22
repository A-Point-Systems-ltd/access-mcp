# PLAN — הפיכת הריפו הזה לריפו ההפצה הרשמי (dist) · v2

> נגזר ממסמך התוכנית המלא בריפו המוצר:
> `MS.Access.MCP/docs/plugin-platforms-development-plan.md` (v2, בראנץ' `claude/plugin-development-plan-g5xjdm`).
> **שינויים מ־v1 (אחרי סבב ביקורת):** ה־exe מגיע למשתמש דרך **bootstrap** ולא
> "הזרקה בזמן פרסום" (קבצים שאינם בגיט לא מגיעים למשתמש — Claude Code משכפל את
> תיקיית הפלאגין מהריפו); נוספה חבילת **Agent Plugin קנונית** אחת שמשרתת גם את
> Cursor ו־VS Code/Copilot; נוסף `release-manifest.json` (provenance).
>
> הריפו הזה הוא הציבורי היחיד של המוצר — האתר כבר מצביע עליו, ולכן הוא ממלא את
> תפקיד `accessmcp-dist` מ־RELEASE-AND-PUBLISH §1.3 (חוב #10). אין ריפו חדש.

## מה הריפו הזה יהיה

1. **GitHub Releases ציבוריים** — `accessmcp.exe`, `accessmcp.mcpb`,
   `SHA256SUMS.txt`, **`release-manifest.json`** (version, source commit, run id,
   hashes, מצב חתימה) + GitHub Artifact Attestations. מפורסמים אוטומטית מריפו
   המוצר הפרטי (cross-repo; GitHub App token או fine-grained PAT מוגבל לריפו הזה,
   `contents:write` בלבד). קוד לא עובר — רק artifacts.
2. **חבילת Agent Plugin קנונית** — `agent-plugin/` אחת: `plugin.json`, `mcp.json`,
   `skills/` (3), `bootstrap/`. ממנה נגזרים כל הקליינטים; **אין עותקי skills פר
   פלטפורמה**.
3. **Marketplace לפלאגין Claude Code** — `.claude-plugin/marketplace.json` **בשורש**
   (דרישה קשיחה), כך ש־`/plugin marketplace add A-Point-Systems-ltd/access-mcp`
   עובד לכל אחד. הפלאגין = adapter דק מעל החבילה הקנונית.
4. **Bootstrap** — `bootstrap.ps1` שה־`mcp.json` מפעיל: מוודא
   `%LOCALAPPDATA%\Programs\AccessMCP\accessmcp.exe` (המיקום הקנוני של המתקין —
   עותק אחד לכל הקליינטים); אם חסר/ישן — מוריד מה־Release, **מאמת SHA256 מול
   `release-manifest.json`** (ובהמשך גם חתימת EV), שומר ומריץ; על פלטפורמה לא
   נתמכת (WSL/macOS/Linux/Remote) נכשל עם הודעה ברורה. **שום exe לא יושב בגיט.**
5. **תבניות התקנה** לכל הקליינטים + המתקין `install-accessmcp.ps1`.

## מבנה יעד

```
access-mcp/
├── .claude-plugin/marketplace.json      ← בשורש; מצביע על ./claude-plugin
├── claude-plugin/                       ← adapter: plugin.json + .mcp.json → bootstrap
│   └── .claude-plugin/plugin.json
├── agent-plugin/                        ← החבילה הקנונית (Cursor / VS Code / בסיס לקלוד)
│   ├── plugin.json
│   ├── mcp.json
│   ├── skills/{access-inspect-db,access-health-report,access-modernization-plan}/
│   └── bootstrap/bootstrap.ps1 · release-manifest.json
├── templates/{claude-desktop,claude-code,cursor,vscode,codex}/
├── installer/install-accessmcp.ps1 · DOCTOR-SPEC.md
├── compliance/preflight-checklist.md    ← שער לפני כל הגשה ל־directory
├── LICENSE (EULA קנייני)  ·  README.md (חדש)
└── Releases: exe · mcpb · SHA256SUMS · release-manifest.json (מריפו המוצר)
```

## משימות (לפי סדר)

- [ ] **ניקוי הדור הקודם:** README v2.1.0 (`MS.Access.MCP.exe`), `releases/Coming
      soon.txt`, `rules/`, `skills/` הישנים — יורדים/מוחלפים.
- [ ] **LICENSE** — חוסם כל הגשה.
- [ ] סנכרון תכני `packaging/` מריפו המוצר (מקור העריכה נשאר שם; sync ב־workflow
      הפרסום — לא עריכה כפולה ביד).
- [ ] `agent-plugin/` קנונית + `bootstrap.ps1` + adapter של Claude Code.
- [ ] README חדש: **Choose your AI client** — Claude Desktop (mcpb) · Claude Code
      (plugin) · Cursor (Add to Cursor / Agent Plugin) · VS Code+Copilot (Install
      link / Agent Plugin) · Codex (config) · כל קליינט MCP (exe+stdio); ומתחת —
      Direct download עם הלינק היציב `releases/latest/download/accessmcp.exe`.
- [ ] `compliance/preflight-checklist.md` (privacy, support, annotations,
      allowlist, אייקונים, הצהרת Windows, מסלול דמו לסוקר).
- [ ] אימות קצה־לקצה על **Windows VM נקי**:
      `claude plugin validate --strict` → `/plugin marketplace add ./access-mcp` →
      `/plugin install accessmcp@accessmcp` → bootstrap מוריד ומאמת → `access_login`
      → כלי קריאה; ואז מטריצת ה־lifecycle (install/upgrade/uninstall/reinstall,
      פלאגין+exe ידני יחד, שני קליינטים על אותו exe).
- [ ] אחרי פרסום ו־Preflight: **הגשה אחת דרך ה־submission flow של Anthropic**
      (ה־community repo הוא read-only mirror — לא PR); ‏Cursor — אחרי בירור מדיניות
      open-source מול binary קנייני; ‏VS Code — לפי מנגנון ההפצה שלהם.

## מה אסור שיקרה כאן

- שום קוד מוצר, חוזה, סוד או endpoint פנימי — כולל בתוך ה־bootstrap (הוא ציבורי:
  מוריד־ומאמת בלבד).
- שום exe בהיסטוריית git.
- מסלול ההורדה הישירה לא נשבר: ה־exe מה־Release עובד לבד, בלי אף קובץ מהריפו.
- ה־slug ‏`accessmcp` לא משתנה אחרי הפרסום הראשון — נעול לתמיד.
