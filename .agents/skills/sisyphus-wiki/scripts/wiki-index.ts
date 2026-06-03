#!/usr/bin/env bun
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { appendGraph, extractFrontmatter, findMarkdownFiles, nowIso, parseArgs, printJson, relativeToRoot, repoKnowledgeRoot, writeIndex } from "./wiki-lib";

const help = `Usage:
  bun .agents/skills/sisyphus-wiki/scripts/wiki-index.ts --rebuild [--root .sisyphus/knowledge]
`;

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.has("help")) {
    process.stdout.write(help);
    process.exit(0);
  }
  const root = repoKnowledgeRoot(args);
  const entriesRoot = join(root, "entries");
  const nodes = [];
  const edges = [];
  for (const file of findMarkdownFiles(entriesRoot)) {
    const fm = extractFrontmatter(readFileSync(file, "utf8"));
    const id = String(fm.id ?? "");
    if (!id) continue;
    nodes.push({
      id,
      title: String(fm.title ?? id),
      type: String(fm.type ?? "reference"),
      status: String(fm.status ?? "active"),
      path: relativeToRoot(root, file),
      tags: Array.isArray(fm.tags) ? fm.tags.map(String) : []
    });
    const relations = Array.isArray(fm.relations) ? fm.relations as Record<string, string>[] : [];
    for (const relation of relations) {
      if (relation.type && relation.target) edges.push({ from: id, to: relation.target, type: relation.type });
    }
  }
  const ts = nowIso();
  writeIndex(root, { version: 1, updated_at: ts, nodes, edges });
  appendGraph(root, { ts, event: "index.rebuilt", nodes: nodes.length, edges: edges.length });
  printJson({ ok: true, nodes: nodes.length, edges: edges.length });
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.stderr.write(help);
  process.exit(1);
}
