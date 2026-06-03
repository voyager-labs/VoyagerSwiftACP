#!/usr/bin/env bun
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { CONFIDENCES, ENTRY_TYPES, STATUSES, appendGraph, ensureDir, entryPath, many, nowIso, one, parseArgs, parseCsv, parseRelation, parseTypedObject, printJson, renderEntry, repoKnowledgeRoot, requireOne, relativeToRoot, upsertIndex } from "./wiki-lib";

const help = `Usage:
  bun .agents/skills/sisyphus-wiki/scripts/wiki-write.ts --type decision --title "..." --insight "..." [options]

Options:
  --root <path>              Knowledge root (default: .sisyphus/knowledge)
  --id <id>                  Stable entry id (default: kw-YYYYMMDD-title-slug)
  --type <type>              decision|finding|pattern|preference|question|reference|proposal
  --title <title>            Entry title
  --status <status>          active|superseded|resolved|archived (default: active)
  --confidence <value>       low|medium|high (default: medium)
  --tags <a,b,c>             Comma-separated tags
  --source <type:id>         Repeatable source link
  --relation <type:target>   Repeatable graph relation
  --affected <type:id>       Repeatable affected artifact
  --context <text>           Context section
  --insight <text>           Durable insight section
  --implications <text>      Implications section
  --next-action <text>       Next action section
  --body-file <path>         Optional Markdown body file with four sections
  --dry-run                  Print result without writing
`;

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.has("help")) {
    process.stdout.write(help);
    process.exit(0);
  }

  const root = repoKnowledgeRoot(args);
  const type = requireOne(args, "type");
  const status = one(args, "status", "active");
  const confidence = one(args, "confidence", "medium");
  if (!ENTRY_TYPES.includes(type as never)) throw new Error(`Invalid --type: ${type}`);
  if (!STATUSES.includes(status as never)) throw new Error(`Invalid --status: ${status}`);
  if (!CONFIDENCES.includes(confidence as never)) throw new Error(`Invalid --confidence: ${confidence}`);

  const title = requireOne(args, "title");
  const ts = nowIso();
  const bodyFile = one(args, "body-file");
  const body = bodyFile ? readFileSync(bodyFile, "utf8") : "";
  const input = {
    id: one(args, "id") || undefined,
    title,
    type: type as never,
    status: status as never,
    created_at: one(args, "created-at", ts),
    updated_at: ts,
    confidence: confidence as never,
    tags: parseCsv(one(args, "tags")),
    sources: many(args, "source").map(parseTypedObject),
    relations: many(args, "relation").map(parseRelation),
    affected: many(args, "affected").map(parseTypedObject),
    context: one(args, "context") || body,
    insight: requireOne(args, "insight"),
    implications: one(args, "implications"),
    nextAction: one(args, "next-action")
  };

  const rendered = renderEntry(input);
  const outputPath = entryPath(root, input.created_at, title);
  const relPath = relativeToRoot(root, outputPath);
  const existed = existsSync(outputPath);
  const node = { id: rendered.id, title, type, status, path: relPath, tags: input.tags };

  if (!args.has("dry-run")) {
    ensureDir(dirname(outputPath));
    writeFileSync(outputPath, rendered.markdown);
    upsertIndex(root, node, input.relations, ts);
    appendGraph(root, { ts, event: existed ? "node.updated" : "node.created", id: rendered.id, path: relPath });
    for (const relation of input.relations) appendGraph(root, { ts, event: "edge.created", from: rendered.id, to: relation.target, type: relation.type });
  }

  printJson({ ok: true, dry_run: args.has("dry-run"), id: rendered.id, path: relPath, existed, relations: input.relations.length });
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.stderr.write(help);
  process.exit(1);
}
