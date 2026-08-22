# PLAN — הפיכת הריפו הזה לריפו ההפצה הרשמי (dist)

> נגזר ממסמך התוכנית המלא בריפו המוצר:
> `MS.Access.MCP/docs/plugin-platforms-development-plan.md` (בראנץ' `claude/plugin-development-plan-g5xjdm`).
> הריפו הזה הוא הציבורי היחיד של המוצר — האתר כבר מצביע עליו
> (`access-mcp.ai` → GitHub / Releases), ולכן הוא ממלא את תפקיד `accessmcp-dist`
> מ־RELEASE-AND-PUBLISH §1.3 (חוב טכני #10). אין צורך בריפו חדש.

## מה הריפו הזה יהיה

1. **GitHub Releases ציבוריים** — `accessmcp.exe`, `accessmcp.mcpb`, `SHA256SUMS.txt`.
   מפורסמים אוטומטית מ־`release.yml` של ריפו המוצר הפרטי (cross-repo publish עם
   token ייעודי). הקוד לא עובר — רק ה־artifacts.
2. **Marketplace לפלאגין Claude Code** — `.claude-plugin/marketplace.json` **בשורש**
   (דרישה קשיחה של Claude Code), כך ש־
   `/plugin marketplace add A-Point-Systems-ltd/access-mcp` עובד לכל אחד.
3. **הפלאגין עצמו** — `claude-plugin/` עם `plugin.json`, `.mcp.json`, שלוש SKILLs,
   ו־`bin/accessmcp.exe` שמוזרק **בזמן פרסום בלבד** (לא בגיט — ‎.gitignore) כדי
   שעדכון פלאגין יעדכן גם את ה־exe בלי לנפח את היסטוריית הריפו.
4. **תבניות התקנה** לכל הקליינטים — Claude Desktop, Claude Code, Cursor, Codex —
   והמתקין `install-accessmcp.ps1` (per-user, ללא אדמין).

## מבנה יעד

```
access-mcp/
├── .claude-plugin/marketplace.json      ← בשורש; מצביע על ./claude-plugin
├── claude-plugin/
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json                        ← ${CLAUDE_PLUGIN_ROOT}/bin/accessmcp.exe
│   ├── bin/                             ← מוזרק בפרסום (git-ignored)
│   └── skills/
│       ├── access-inspect-db/
│       ├── access-health-report/
│       └── access-modernization-plan/
├── templates/{claude-desktop,claude-code,cursor,codex}/
├── installer/install-accessmcp.ps1 · DOCTOR-SPEC.md
├── LICENSE (EULA קנייני — נוסח מדניאל)
└── README.md (חדש — ראה למטה)
```

## משימות (לפי סדר)

- [ ] **ניקוי הדור הקודם:** README הנוכחי (v2.1.0, `MS.Access.MCP.exe`),
      `releases/Coming soon.txt`, `rules/`, `skills/` הישנים — יורדים או מוחלפים.
      השם הקנוני הוא `accessmcp.exe` והגרסה מסונכרנת אוטומטית.
- [ ] **LICENSE** — חוסם כל הגשה לספרייה חיצונית.
- [ ] העתקת תכני `packaging/` מריפו המוצר (מקור האמת נשאר שם; סנכרון רק דרך
      workflow הפרסום — בלי עריכה כפולה ביד).
- [ ] `.gitignore` ל־`claude-plugin/bin/`.
- [ ] README חדש: ארבעת מסלולי ההתקנה לפי סדר — פלאגין Claude Code · ‎.mcpb
      ל־Claude Desktop · Add to Cursor (דיפלינק) · ידני (exe + `mcp.json`) —
      עם הלינק היציב `releases/latest/download/accessmcp.exe`.
- [ ] אימות קצה־לקצה מקומי לפני פרסום:
      `claude plugin validate --strict` → `/plugin marketplace add ./access-mcp` →
      `/plugin install accessmcp@accessmcp` → `access_login` → כלי קריאה.
- [ ] אחרי הפרסום: הגשה ל־`anthropics/claude-plugins-community` (עדכון אוטומטי
      כברירת מחדל), ואז ל־directory הרשמי.

## מה אסור שיקרה כאן

- שום קוד מוצר, חוזה או תוכנית פנימית לא נכנסים לריפו הזה — artifacts ותצורה בלבד.
- מסלול ההורדה הישירה לא נשבר: ה־exe מה־Release עובד לבד, בלי אף קובץ מהריפו.
- ה־slug ‏`accessmcp` לא משתנה אחרי הפרסום הראשון — נעול לתמיד.
