#!/usr/bin/env bun
import { appendFileSync } from "node:fs";
import { join } from "node:path";
import { ensureDir, nowIso, one, parseArgs, printJson, repoKnowledgeRoot, requireOne } from "./wiki-lib";

const help = `Usage:
  bun .agents/skills/sisyphus-wiki/scripts/wiki-session-event.ts --session-id <id> --event knowledge.candidate --summary "..."

Options:
  --root <path>           Knowledge root (default: .sisyphus/knowledge)
  --session-id <id>       Session identifier
  --event <name>          Event name (default: knowledge.candidate)
  --summary <text>        Event summary
  --tags <a,b,c>          Optional comma-separated tags
  --candidate             Also append to inbox/pending-extractions.jsonl
`;

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.has("help")) {
    process.stdout.write(help);
    process.exit(0);
  }
  const root = repoKnowledgeRoot(args);
  const sessionId = requireOne(args, "session-id");
  const event = one(args, "event", "knowledge.candidate");
  const summary = requireOne(args, "summary");
  const ts = nowIso();
  const payload = { ts, event, session_id: sessionId, summary, tags: one(args, "tags") };

  const sessionsDir = join(root, "sessions");
  ensureDir(sessionsDir);
  appendFileSync(join(sessionsDir, `${sessionId}.jsonl`), `${JSON.stringify(payload)}\n`);

  if (args.has("candidate")) {
    const inbox = join(root, "inbox");
    ensureDir(inbox);
    appendFileSync(join(inbox, "pending-extractions.jsonl"), `${JSON.stringify(payload)}\n`);
  }

  printJson({ ok: true, path: `sessions/${sessionId}.jsonl`, candidate: args.has("candidate") });
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.stderr.write(help);
  process.exit(1);
}
