#!/usr/bin/env bun
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ENTRY_TYPES, RELATIONS, STATUSES, extractFrontmatter, findMarkdownFiles, parseArgs, printJson, readIndex, repoKnowledgeRoot } from "./wiki-lib";

const help = `Usage:
  bun .agents/skills/sisyphus-wiki/scripts/wiki-validate.ts [--root .sisyphus/knowledge]
`;

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.has("help")) {
    process.stdout.write(help);
    process.exit(0);
  }
  const root = repoKnowledgeRoot(args);
  const errors: string[] = [];
  const ids = new Set<string>();
  const files = findMarkdownFiles(join(root, "entries"));
  for (const file of files) {
    const fm = extractFrontmatter(readFileSync(file, "utf8"));
    const id = String(fm.id ?? "");
    if (!id) errors.push(`${file}: missing id`);
    if (ids.has(id)) errors.push(`${file}: duplicate id ${id}`);
    ids.add(id);
    if (!fm.title) errors.push(`${file}: missing title`);
    if (!ENTRY_TYPES.includes(String(fm.type) as never)) errors.push(`${file}: invalid type ${String(fm.type)}`);
    if (!STATUSES.includes(String(fm.status) as never)) errors.push(`${file}: invalid status ${String(fm.status)}`);
    const relations = Array.isArray(fm.relations) ? fm.relations as Record<string, string>[] : [];
    for (const relation of relations) {
      if (!RELATIONS.includes(String(relation.type) as never)) errors.push(`${file}: invalid relation ${String(relation.type)}`);
      if (!relation.target) errors.push(`${file}: relation missing target`);
    }
  }
  const index = readIndex(root);
  for (const node of index.nodes) {
    if (!ids.has(node.id)) errors.push(`index.json: node without entry ${node.id}`);
  }
  const graphPath = join(root, "graph.jsonl");
  try {
    const graph = readFileSync(graphPath, "utf8").split("\n").filter(Boolean);
    graph.forEach((line, idx) => {
      try { JSON.parse(line); } catch { errors.push(`graph.jsonl:${idx + 1}: invalid JSON`); }
    });
  } catch {
    // graph.jsonl is optional until the first write.
  }
  printJson({ ok: errors.length === 0, files: files.length, errors });
  if (errors.length > 0) process.exit(1);
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.stderr.write(help);
  process.exit(1);
}
