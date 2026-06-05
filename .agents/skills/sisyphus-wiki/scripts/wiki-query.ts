#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { many, one, parseArgs, printJson, readIndex, repoKnowledgeRoot } from "./wiki-lib";

const help = `Usage:
  bun .agents/skills/sisyphus-wiki/scripts/wiki-query.ts [--tag traceability] [--type finding] [--text review] [--limit 10]
`;

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.has("help")) {
    process.stdout.write(help);
    process.exit(0);
  }
  const root = repoKnowledgeRoot(args);
  const index = readIndex(root);
  const tags = many(args, "tag").flatMap((value) => value.split(",").map((item) => item.trim()).filter(Boolean));
  const type = one(args, "type");
  const status = one(args, "status");
  const text = one(args, "text").toLowerCase();
  const limit = Number(one(args, "limit", "20"));
  const results = [];
  for (const node of index.nodes) {
    if (type && node.type !== type) continue;
    if (status && node.status !== status) continue;
    if (tags.length > 0 && !tags.every((tag) => node.tags.includes(tag))) continue;
    const path = join(root, node.path);
    const content = existsSync(path) ? readFileSync(path, "utf8") : "";
    if (text && !`${node.title}\n${content}`.toLowerCase().includes(text)) continue;
    results.push({ ...node, preview: content.split("\n").find((line) => line.trim() && !line.startsWith("---")) ?? "" });
    if (results.length >= limit) break;
  }
  printJson({ ok: true, count: results.length, results });
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.stderr.write(help);
  process.exit(1);
}
