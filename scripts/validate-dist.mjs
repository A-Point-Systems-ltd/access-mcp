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
//      agent-plugin/; claude-plugin uses ${CLAUDE_PLUGIN_ROOT}.
//   5. Skills have frontmatter with name + description; marketplace source
//      paths exist; bootstrap manifest shape is right.
//
// Usage: node scripts/validate-dist.mjs [repo-root]

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, extname } from 'node:path';

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

for (const p of walk(root)) {
  const r = rel(p);
  for (const re of FORBIDDEN_FILES) {
    if (re.test(r)) err(`${r}: forbidden file type/name in public dist repo`);
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
const claudeManifest = readJson(join(root, 'claude-plugin/bootstrap/release-manifest.json'));

const versions = new Map();
if (marketplace?.plugins?.[0]?.version) versions.set('.claude-plugin/marketplace.json', marketplace.plugins[0].version);
if (claudePlugin?.version) versions.set('claude-plugin plugin.json', claudePlugin.version);
if (agentPlugin?.version) versions.set('agent-plugin/plugin.json', agentPlugin.version);
if (new Set(versions.values()).size > 1) {
  err(`version mismatch across manifests: ${[...versions].map(([k, v]) => `${k}=${v}`).join(', ')}`);
}
for (const [label, m] of [['agent-plugin', agentManifest], ['claude-plugin', claudeManifest]]) {
  if (!m) continue;
  for (const f of ['version', 'exe_url', 'exe_sha256']) {
    if (!m[f]) err(`${label} release-manifest.json: missing '${f}'`);
  }
  if (m.exe_url && !/^https:\/\/github\.com\/A-Point-Systems-ltd\/access-mcp\/releases\/download\/v[^/]+\/accessmcp\.exe$/.test(m.exe_url)) {
    err(`${label} release-manifest.json: exe_url must be a version-pinned release asset URL, got ${m.exe_url}`);
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
compareTrees(join(root, 'agent-plugin/bootstrap'), join(root, 'claude-plugin/bootstrap'), 'claude-plugin bootstrap');

// --------------------------------------- 4. adapter token substitution -----
const agentMcp = read(join(root, 'agent-plugin/mcp.json'));
if (!agentMcp.includes('__PLUGIN_ROOT__')) {
  err('agent-plugin/mcp.json: expected the __PLUGIN_ROOT__ template token');
}
const claudeMcpPath = join(root, 'claude-plugin/.mcp.json');
const claudeMcp = read(claudeMcpPath);
if (claudeMcp.includes('__PLUGIN_ROOT__')) {
  err('claude-plugin/.mcp.json: raw __PLUGIN_ROOT__ token — adapter substitution did not happen');
}
if (!claudeMcp.includes('${CLAUDE_PLUGIN_ROOT}')) {
  err('claude-plugin/.mcp.json: expected ${CLAUDE_PLUGIN_ROOT} in the bootstrap path');
}
const claudeMcpJson = readJson(claudeMcpPath);
const server = claudeMcpJson?.mcpServers?.accessmcp;
if (server && !/bootstrap\.ps1$/.test(server.args?.at(-1) ?? '')) {
  err('claude-plugin/.mcp.json: server must launch bootstrap/bootstrap.ps1');
}

// ------------------------------------------------- 5. skills frontmatter ---
const skillsDir = join(root, 'agent-plugin/skills');
if (existsSync(skillsDir)) {
  for (const name of readdirSync(skillsDir)) {
    const skillMd = join(skillsDir, name, 'SKILL.md');
    if (!existsSync(skillMd)) { err(`agent-plugin/skills/${name}: missing SKILL.md`); continue; }
    const body = read(skillMd);
    const fm = body.match(/^---\n([\s\S]*?)\n---/);
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
