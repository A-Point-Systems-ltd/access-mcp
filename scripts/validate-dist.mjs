#!/usr/bin/env node
// validate-dist.mjs — the dist repo's own gate. Runs on every push (CI) and
// inside the product repo's sync workflow. Fails loudly; a public repo has
// no "fix it later".
//
// Checks:
//   1. Supply-chain: no forbidden files/paths/patterns anywhere in the tree
//      (plan §2.5 — secrets, internal domains, product-repo paths, binaries).
//   2. Manifests parse and agree: one version across marketplace.json,
//      claude-plugin/plugin.json, agent-plugin/plugin.json and both
//      release-manifest.json copies.
//   3. Derived copies match the canonical package byte-for-byte
//      (claude-plugin skills/ and bootstrap/ vs agent-plugin's).
//   4. Adapter substitution happened: no raw __PLUGIN_ROOT__ token outside
//      agent-plugin/; both packages use ${CLAUDE_PLUGIN_ROOT} (Cursor expands
//      it, not the standard ${PLUGIN_ROOT}).
//   5. Skills have frontmatter with name + description; marketplace source
//      paths exist; bootstrap manifest shape is right.
//   6. Bundled layout: the Claude Code plugin ships claude-plugin/server/
//      accessmcp.exe (the plugin directory refuses a download-and-run
//      launcher). Its bytes match server/release-manifest.json and it is
//      under GitHub's 100 MB limit. That exe is the ONLY binary allowed here:
//      no top-level claude-plugin/bin/ (Claude Code puts it on the Bash PATH,
//      and claude.ai, Cowork and org distribution refuse it), and no older
//      exes in the tree (Claude Code clones the whole repo; older exes stay
//      on the GitHub Releases).
//
// Usage: node scripts/validate-dist.mjs [repo-root]

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const root = process.argv[2] ?? process.cwd();
const errors = [];
const err = (msg) => errors.push(msg);

// ---------------------------------------------------------------- helpers --
function* walk(dir) {
  for (const name of readdirSync(dir)) {
    if (name === '.git' || name === 'node_modules') continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* walk(p);
    else yield p;
  }
}

const rel = (p) => relative(root, p).replaceAll('\\', '/');
const read = (p) => readFileSync(p, 'utf8');
const readJson = (p, label) => {
  try { return JSON.parse(read(p)); }
  catch (e) { err(`${label ?? rel(p)}: invalid JSON — ${e.message}`); return null; }
};

// -------------------------------------------------- 1. supply-chain scans --
const FORBIDDEN_FILES = [
  /(^|\/)\.dev\.vars(\..*)?$/,
  /(^|\/)\.env(\..*)?$/,
  /\.(sql|accdb|mdb|laccdb|adp)$/i,
  /\.(exe|dll|mcpb|zip|7z|msi)$/i, // binaries never live in git here
  /\.(pfx|p12|pem|key|cer|der|jks|keystore)$/i, // key material — especially once the EV cert exists
  /(^|\/)wrangler\.toml$/,
];
const FORBIDDEN_CONTENT = [
  // secret-shaped strings
  { re: /-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----/, why: 'private key material' },
  { re: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/, why: 'GitHub token' },
  { re: /\bAKIA[0-9A-Z]{16}\b/, why: 'AWS access key' },
  { re: /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/, why: 'JWT' },
  // internal-only surfaces that must never appear in the public repo
  { re: /[A-Za-z0-9-]+\.workers\.dev/, why: 'internal workers.dev host' },
  { re: /ImplementationPlan\//, why: 'private product-repo path' },
  { re: /access-mcp-saas/, why: 'private implementation package name' },
  { re: /CONTRACT-?REFERENCE/i, why: 'private contract document reference' },
  { re: /RUNBOOK-HE|SETUP-GUIDE-HE|QA-PROD/i, why: 'private runbook reference' },
];
const TEXT_EXT = new Set(['.md', '.json', '.jsonc', '.ps1', '.toml', '.yml', '.yaml', '.mjs', '.js', '.txt', '']);
// The only binary allowed: the Claude Code plugin's exe. Section 6 checks its
// bytes against its manifest.
const ALLOWED_BINARIES = [
  /^claude-plugin\/server\/accessmcp\.exe$/,
];

for (const p of walk(root)) {
  const r = rel(p);
  for (const re of FORBIDDEN_FILES) {
    if (re.test(r) && !ALLOWED_BINARIES.some((ok) => ok.test(r))) err(`${r}: forbidden file type/name in public dist repo`);
  }
  if (TEXT_EXT.has(extname(p).toLowerCase())) {
    const body = read(p);
    for (const { re, why } of FORBIDDEN_CONTENT) {
      // this validator documents the patterns it hunts — exempt itself
      if (r === 'scripts/validate-dist.mjs') continue;
      if (re.test(body)) err(`${r}: forbidden content (${why})`);
    }
  }
}

// ------------------------------------------- 2. manifests parse and agree --
const marketplace = readJson(join(root, '.claude-plugin/marketplace.json'));
const claudePlugin = readJson(join(root, 'claude-plugin/.claude-plugin/plugin.json'));
const agentPlugin = readJson(join(root, 'agent-plugin/plugin.json'));
const agentManifest = readJson(join(root, 'agent-plugin/bootstrap/release-manifest.json'));
// The Claude Code plugin ships the release exe in claude-plugin/server/ with its manifest; the 2.5.x bootstrap and
// the 2.7.0 bin/ layout are gone from main.
const claudeManifest = readJson(join(root, 'claude-plugin/server/release-manifest.json'));
if (existsSync(join(root, 'claude-plugin/bin'))) {
  err('claude-plugin/bin: a top-level bin/ is reserved in Claude Code plugins (put on the Bash PATH; claude.ai refuses it) — the exe lives in claude-plugin/server/');
}
if (existsSync(join(root, 'previous-versions'))) {
  err('previous-versions: older exes do not stay in the tree (Claude Code clones the whole repo) — they are on the GitHub Releases');
}

const versions = new Map();
if (marketplace?.plugins?.[0]?.version) versions.set('.claude-plugin/marketplace.json', marketplace.plugins[0].version);
if (claudePlugin?.version) versions.set('claude-plugin plugin.json', claudePlugin.version);
if (agentPlugin?.version) versions.set('agent-plugin/plugin.json', agentPlugin.version);
// The pinned release manifests are part of the same agreement — a manifest
// drifting to 9.9.9 while the plugins say 2.3.1 must fail here, not only in
// the release pipeline (review round 3, §7).
if (agentManifest?.version) versions.set('agent-plugin release-manifest.json', agentManifest.version);
if (claudeManifest?.version) versions.set('claude-plugin release-manifest.json', claudeManifest.version);
if (new Set(versions.values()).size > 1) {
  err(`version mismatch across manifests: ${[...versions].map(([k, v]) => `${k}=${v}`).join(', ')}`);
}
if (!agentPlugin?.$schema || !/agent-plugins\.org\/schemas\//.test(agentPlugin.$schema)) {
  err('agent-plugin/plugin.json: missing the Agent Plugins 1.0 $schema declaration');
}
for (const [label, m] of [['agent-plugin', agentManifest], ['claude-plugin', claudeManifest]]) {
  if (!m) continue;
  for (const f of ['version', 'exe_url', 'exe_sha256']) {
    if (!m[f]) err(`${label} release-manifest.json: missing '${f}'`);
  }
  const urlTag = m.exe_url?.match(/^https:\/\/github\.com\/A-Point-Systems-ltd\/access-mcp\/releases\/download\/v([^/]+)\/accessmcp\.exe$/)?.[1];
  if (m.exe_url && !urlTag) {
    err(`${label} release-manifest.json: exe_url must be a version-pinned release asset URL, got ${m.exe_url}`);
  }
  if (urlTag && m.version && urlTag !== m.version) {
    err(`${label} release-manifest.json: exe_url tag v${urlTag} != version ${m.version}`);
  }
  if (m.exe_sha256 && !/^[0-9a-fA-F]{64}$/.test(m.exe_sha256)) {
    err(`${label} release-manifest.json: exe_sha256 is not 64 hex chars`);
  }
}

if (marketplace?.plugins) {
  for (const plugin of marketplace.plugins) {
    const src = join(root, plugin.source ?? '');
    if (!existsSync(src)) err(`marketplace.json: source '${plugin.source}' does not exist`);
    if (plugin.name !== 'accessmcp') err(`marketplace.json: plugin slug '${plugin.name}' — the slug is permanent, expected 'accessmcp'`);
  }
}

// -------------------------------- 3. derived copies match canonical bytes --
function compareTrees(canonDir, copyDir, label) {
  if (!existsSync(canonDir) || !existsSync(copyDir)) {
    err(`${label}: missing ${!existsSync(canonDir) ? rel(canonDir) : rel(copyDir)}`);
    return;
  }
  const canonFiles = [...walk(canonDir)].map((p) => relative(canonDir, p).replaceAll('\\', '/')).sort();
  const copyFiles = [...walk(copyDir)].map((p) => relative(copyDir, p).replaceAll('\\', '/')).sort();
  if (canonFiles.join('\n') !== copyFiles.join('\n')) {
    err(`${label}: file lists differ (canonical: ${canonFiles.length}, copy: ${copyFiles.length})`);
    return;
  }
  for (const f of canonFiles) {
    if (read(join(canonDir, f)) !== read(join(copyDir, f))) {
      err(`${label}: ${f} drifted from the canonical copy — edit agent-plugin/ (upstream), not the adapter`);
    }
  }
}
compareTrees(join(root, 'agent-plugin/skills'), join(root, 'claude-plugin/skills'), 'claude-plugin skills');
if (existsSync(join(root, 'claude-plugin/bootstrap'))) {
  err('claude-plugin/bootstrap: left over — the bundled plugin does not use the bootstrap');
}

// --------------------------------------- 4. adapter token substitution -----
// Canonical package = Agent Plugins 1.0 ($schema declared), but its plugin
// root variable is ${CLAUDE_PLUGIN_ROOT}, NOT the standard ${PLUGIN_ROOT}:
// Cursor expands ${CURSOR_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_ROOT} in an Agent
// Plugin's mcp.json and documents that it does not expand ${PLUGIN_ROOT}, so
// the standard token left the server path unresolved there.
const agentMcp = read(join(root, 'agent-plugin/mcp.json'));
if (!agentMcp.includes('${CLAUDE_PLUGIN_ROOT}') || agentMcp.includes('${PLUGIN_ROOT}')) {
  err('agent-plugin/mcp.json: expected ${CLAUDE_PLUGIN_ROOT} and no ${PLUGIN_ROOT} (Cursor does not expand the standard variable)');
}
if (agentMcp.includes('__PLUGIN_ROOT__')) {
  err('agent-plugin/mcp.json: legacy __PLUGIN_ROOT__ token — the canonical package uses ${CLAUDE_PLUGIN_ROOT}');
}
// Agent Plugins 1.0 requires the $schema declaration on the MCP config
// itself, not only on plugin.json — a conformant client MUST reject the
// component otherwise (review round 4, §1).
const agentMcpJson = readJson(join(root, 'agent-plugin/mcp.json'));
if (!agentMcpJson?.$schema || !/agent-plugins\.org\/schemas\/.*mcp\.schema\.json/.test(agentMcpJson.$schema)) {
  err('agent-plugin/mcp.json: missing the Agent Plugins 1.0 mcp.schema.json $schema declaration');
}
const claudeMcpPath = join(root, 'claude-plugin/.mcp.json');
const claudeMcp = read(claudeMcpPath);
if (claudeMcp.includes('${PLUGIN_ROOT}') || claudeMcp.includes('__PLUGIN_ROOT__')) {
  err('claude-plugin/.mcp.json: un-substituted plugin-root token — adapter derivation did not happen');
}
if (!claudeMcp.includes('${CLAUDE_PLUGIN_ROOT}')) {
  err('claude-plugin/.mcp.json: expected ${CLAUDE_PLUGIN_ROOT} in the launch path');
}
// Adapter manifest = canonical manifest minus $schema (Claude Code is not
// an Agent Plugins consumer) plus the per-user userConfig that asks for the
// database; everything else must match. The server refuses to start without
// a database, so the userConfig and the env that carries it are required.
if (claudePlugin && agentPlugin) {
  const { $schema: _s, ...agentRest } = agentPlugin;
  const { userConfig: _u, ...claudeRest } = claudePlugin;
  if (JSON.stringify(claudeRest) !== JSON.stringify(agentRest)) {
    err('claude-plugin plugin.json drifted from agent-plugin/plugin.json (expected: identical minus $schema and userConfig)');
  }
  if (!claudePlugin.userConfig?.access_file_path) {
    err('claude-plugin plugin.json: userConfig.access_file_path missing — the server cannot start without a database');
  }
}
const claudeMcpJson = readJson(claudeMcpPath);
// The Claude adapter is NOT an Agent Plugins consumer — sync strips the
// agent-plugins $schema during derivation; its presence means derivation
// did not run.
if (claudeMcpJson?.$schema && /agent-plugins\.org/.test(claudeMcpJson.$schema)) {
  err('claude-plugin/.mcp.json: carries the agent-plugins $schema — adapter derivation should strip it');
}
const server = claudeMcpJson?.mcpServers?.accessmcp;
// The exe by a literal path, no arguments, no shell — the form the plugin
// directory follows.
if (server &&
    (server.command !== '${CLAUDE_PLUGIN_ROOT}/server/accessmcp.exe' || (server.args ?? []).length !== 0)) {
  err('claude-plugin/.mcp.json: server must run ${CLAUDE_PLUGIN_ROOT}/server/accessmcp.exe with no arguments');
}
if (server && server.env?.AccessFilePath !== '${user_config.access_file_path}') {
  err('claude-plugin/.mcp.json: server env.AccessFilePath must be ${user_config.access_file_path}');
}
// Cursor has no per-user plugin setting: a fixed env value in the canonical
// package would override the AccessFilePath variable its users set.
if (JSON.parse(agentMcp)?.mcpServers?.accessmcp?.env?.AccessFilePath !== undefined) {
  err('agent-plugin/mcp.json: must not set env.AccessFilePath (it would override the environment variable Cursor users set)');
}

// ------------------------------------------- 6. bundled exe + icon ---------
const MAX_EXE_BYTES = 100 * 1024 * 1024; // GitHub refuses a pushed file over 100 MB
const sha256 = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
function checkExe(dir, manifest, label) {
  const exe = join(dir, 'accessmcp.exe');
  if (!existsSync(exe)) { err(`${label}: accessmcp.exe missing`); return; }
  const size = statSync(exe).size;
  if (size > MAX_EXE_BYTES) err(`${label}/accessmcp.exe: ${size} bytes — over GitHub's 100 MB file limit`);
  if (manifest?.exe_sha256 && sha256(exe) !== manifest.exe_sha256.toLowerCase()) {
    err(`${label}/accessmcp.exe: SHA256 does not match ${label}/release-manifest.json`);
  }
}
checkExe(join(root, 'claude-plugin/server'), claudeManifest, 'claude-plugin/server');
// The release commits the synced tree with git: an ignored exe would ship a plugin without its server while this
// check of the working tree still passed. Only in a git checkout (release.yml's dist-repo, CI).
if (existsSync(join(root, '.git'))) {
  try {
    execFileSync('git', ['-C', root, 'check-ignore', '-q', 'claude-plugin/server/accessmcp.exe'], { stdio: 'ignore' });
    err('claude-plugin/server/accessmcp.exe: ignored by .gitignore — the release commit would leave it out');
  } catch (e) {
    // exit 1 = not ignored (what we want); anything else means git itself failed
    if (e.status !== 1) err(`git check-ignore failed (${e.message}) — cannot tell whether the exe would be committed`);
  }
}

// Listing icon: square PNG, 512–2048 px a side, under 2 MB (plugin directory rule).
const iconPath = join(root, 'claude-plugin/.claude-plugin/icon.png');
if (!existsSync(iconPath)) err('claude-plugin/.claude-plugin/icon.png missing — the plugin directory listing needs it');
if (existsSync(iconPath)) {
  const png = readFileSync(iconPath);
  const isPng = png.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const w = isPng ? png.readUInt32BE(16) : 0, h = isPng ? png.readUInt32BE(20) : 0;
  if (!isPng) err('claude-plugin/.claude-plugin/icon.png: not a PNG');
  else if (w !== h || w < 512 || w > 2048) err(`claude-plugin/.claude-plugin/icon.png: ${w}x${h} — must be square, 512 to 2048 px`);
  if (png.length >= 2 * 1024 * 1024) err('claude-plugin/.claude-plugin/icon.png: 2 MB or more');
}

// ------------------------------------------------- 5. skills frontmatter ---
const skillsDir = join(root, 'agent-plugin/skills');
if (existsSync(skillsDir)) {
  for (const name of readdirSync(skillsDir)) {
    const skillMd = join(skillsDir, name, 'SKILL.md');
    if (!existsSync(skillMd)) { err(`agent-plugin/skills/${name}: missing SKILL.md`); continue; }
    const body = read(skillMd);
    // \r?\n, not \n: the release job syncs+validates on a WINDOWS runner,
    // where git checks files out with CRLF — the exact-\n form rejected
    // every SKILL.md there while passing on every Linux runner (run #3).
    const fm = body.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if (!fm) { err(`skills/${name}/SKILL.md: missing frontmatter`); continue; }
    if (!/^name:\s*\S+/m.test(fm[1])) err(`skills/${name}/SKILL.md: frontmatter missing 'name'`);
    if (!/^description:\s*\S+/m.test(fm[1])) err(`skills/${name}/SKILL.md: frontmatter missing 'description'`);
    if (/PLACEHOLDER/i.test(body)) err(`skills/${name}/SKILL.md: still a placeholder`);
  }
}

// LICENSE placeholder guard: presence of the marker is allowed on branches,
// but the release pipeline greps for it and refuses to ship (see product
// repo release.yml). Here we only warn via a distinct exit-code-0 notice.
const licensePath = join(root, 'LICENSE');
if (!existsSync(licensePath)) {
  err('LICENSE missing — required before anything is published from this repo');
} else if (read(licensePath).includes('PLACEHOLDER-EULA')) {
  console.error('NOTICE: LICENSE is still the placeholder — fine on a branch, blocks a release.');
}

// -------------------------------------------------------------- verdict ----
if (errors.length) {
  console.error(`validate-dist: ${errors.length} problem(s):\n` + errors.map((e) => `  - ${e}`).join('\n'));
  process.exit(1);
}
console.error('validate-dist: OK');
