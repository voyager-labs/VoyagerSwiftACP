import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

export const ENTRY_TYPES = ["decision", "finding", "pattern", "preference", "question", "reference", "proposal"] as const;
export const STATUSES = ["active", "superseded", "resolved", "archived"] as const;
export const CONFIDENCES = ["low", "medium", "high"] as const;
export const RELATIONS = ["relates_to", "derived_from", "affects", "motivates", "supersedes", "contradicts", "resolved_by", "evidence_for", "verified_by", "example_of"] as const;

export type EntryType = (typeof ENTRY_TYPES)[number];
export type EntryStatus = (typeof STATUSES)[number];
export type Confidence = (typeof CONFIDENCES)[number];
export type RelationType = (typeof RELATIONS)[number];

export interface WikiObject {
  type: string;
  id: string;
  path?: string;
  note?: string;
}

export interface WikiRelation {
  type: RelationType;
  target: string;
  note?: string;
}

export interface WikiEntryInput {
  id?: string;
  title: string;
  type: EntryType;
  status: EntryStatus;
  created_at: string;
  updated_at: string;
  confidence: Confidence;
  tags: string[];
  sources: WikiObject[];
  relations: WikiRelation[];
  affected: WikiObject[];
  context: string;
  insight: string;
  implications: string;
  nextAction: string;
}

export interface WikiIndexNode {
  id: string;
  title: string;
  type: string;
  status: string;
  path: string;
  tags: string[];
}

export interface WikiIndexEdge {
  from: string;
  to: string;
  type: string;
}

export interface WikiIndex {
  version: number;
  updated_at: string;
  nodes: WikiIndexNode[];
  edges: WikiIndexEdge[];
}

export function parseArgs(argv: string[]): Map<string, string[]> {
  const args = new Map<string, string[]>();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    const value = next && !next.startsWith("--") ? next : "true";
    if (value !== "true") index += 1;
    args.set(key, [...(args.get(key) ?? []), value]);
  }
  return args;
}

export function one(args: Map<string, string[]>, key: string, fallback = ""): string {
  return args.get(key)?.[0] ?? fallback;
}

export function many(args: Map<string, string[]>, key: string): string[] {
  return args.get(key) ?? [];
}

export function requireOne(args: Map<string, string[]>, key: string): string {
  const value = one(args, key);
  if (!value) throw new Error(`Missing required --${key}`);
  return value;
}

export function repoKnowledgeRoot(args: Map<string, string[]>): string {
  return one(args, "root", ".sisyphus/knowledge");
}

export function ensureDir(path: string): void {
  mkdirSync(path, { recursive: true });
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function slugify(value: string): string {
  return value
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "entry";
}

export function entryId(date: Date, title: string): string {
  const yyyy = date.getFullYear().toString();
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  return `kw-${yyyy}${mm}${dd}-${slugify(title)}`;
}

export function entryPath(root: string, createdAt: string, title: string): string {
  const date = new Date(createdAt);
  const yyyy = date.getFullYear().toString();
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  return join(root, "entries", `${yyyy}-${mm}-${dd}-${slugify(title)}.md`);
}

export function parseCsv(value: string): string[] {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => item.toLowerCase().replace(/[^a-z0-9-]+/g, "-"));
}

export function parseTypedObject(value: string): WikiObject {
  const [type, ...rest] = value.split(":");
  const id = rest.join(":");
  if (!type || !id) throw new Error(`Expected type:id, got ${value}`);
  return { type, id };
}

export function parseRelation(value: string): WikiRelation {
  const [type, ...rest] = value.split(":");
  const target = rest.join(":");
  if (!RELATIONS.includes(type as RelationType)) throw new Error(`Unknown relation type: ${type}`);
  if (!target) throw new Error(`Expected relation:target, got ${value}`);
  return { type: type as RelationType, target };
}

function yamlString(value: string): string {
  return JSON.stringify(value);
}

function yamlInlineArray(values: string[]): string {
  return `[${values.map(yamlString).join(", ")}]`;
}

function yamlObjects(label: string, values: WikiObject[]): string {
  if (values.length === 0) return `${label}: []`;
  return `${label}:\n${values
    .map((item) => {
      const lines = [`  - type: ${yamlString(item.type)}`, `    id: ${yamlString(item.id)}`];
      if (item.path) lines.push(`    path: ${yamlString(item.path)}`);
      if (item.note) lines.push(`    note: ${yamlString(item.note)}`);
      return lines.join("\n");
    })
    .join("\n")}`;
}

function yamlRelations(values: WikiRelation[]): string {
  if (values.length === 0) return "relations: []";
  return `relations:\n${values
    .map((item) => {
      const lines = [`  - type: ${yamlString(item.type)}`, `    target: ${yamlString(item.target)}`];
      if (item.note) lines.push(`    note: ${yamlString(item.note)}`);
      return lines.join("\n");
    })
    .join("\n")}`;
}

export function renderEntry(input: WikiEntryInput): { id: string; markdown: string } {
  const date = new Date(input.created_at);
  const id = input.id || entryId(date, input.title);
  const markdown = `---\n` +
    `id: ${yamlString(id)}\n` +
    `title: ${yamlString(input.title)}\n` +
    `type: ${yamlString(input.type)}\n` +
    `status: ${yamlString(input.status)}\n` +
    `created_at: ${yamlString(input.created_at)}\n` +
    `updated_at: ${yamlString(input.updated_at)}\n` +
    `confidence: ${yamlString(input.confidence)}\n` +
    `tags: ${yamlInlineArray(input.tags)}\n` +
    `${yamlObjects("sources", input.sources)}\n` +
    `${yamlRelations(input.relations)}\n` +
    `${yamlObjects("affected", input.affected)}\n` +
    `---\n\n` +
    `## Context\n\n${input.context.trim() || "N/A"}\n\n` +
    `## Durable insight\n\n${input.insight.trim() || "N/A"}\n\n` +
    `## Implications\n\n${input.implications.trim() || "N/A"}\n\n` +
    `## Next action\n\n${input.nextAction.trim() || "N/A"}\n`;
  return { id, markdown };
}

export function readIndex(root: string): WikiIndex {
  const path = join(root, "index.json");
  if (!existsSync(path)) return { version: 1, updated_at: nowIso(), nodes: [], edges: [] };
  return JSON.parse(readFileSync(path, "utf8"));
}

export function writeIndex(root: string, index: WikiIndex): void {
  ensureDir(root);
  writeFileSync(join(root, "index.json"), `${JSON.stringify(index, null, 2)}\n`);
}

export function appendGraph(root: string, event: Record<string, unknown>): void {
  ensureDir(root);
  appendFileSync(join(root, "graph.jsonl"), `${JSON.stringify(event)}\n`);
}

export function upsertIndex(root: string, node: WikiIndexNode, relations: WikiRelation[], ts: string): WikiIndex {
  const index = readIndex(root);
  index.updated_at = ts;
  index.nodes = index.nodes.filter((candidate) => candidate.id !== node.id).concat(node);
  const nextEdges = relations.map((relation) => ({ from: node.id, to: relation.target, type: relation.type }));
  const edgeKey = (edge: WikiIndexEdge) => `${edge.from}\u0000${edge.to}\u0000${edge.type}`;
  const merged = new Map<string, WikiIndexEdge>();
  for (const edge of [...index.edges.filter((edge) => edge.from !== node.id), ...nextEdges]) merged.set(edgeKey(edge), edge);
  index.edges = [...merged.values()];
  writeIndex(root, index);
  return index;
}

export function extractFrontmatter(markdown: string): Record<string, unknown> {
  if (!markdown.startsWith("---\n")) return {};
  const end = markdown.indexOf("\n---", 4);
  if (end === -1) return {};
  const fm = markdown.slice(4, end).split("\n");
  const result: Record<string, unknown> = {};
  let currentList: string | null = null;
  let currentItem: Record<string, string> | null = null;
  for (const line of fm) {
    const top = line.match(/^([a-z_]+):\s*(.*)$/);
    if (top) {
      currentList = null;
      currentItem = null;
      const [, key, raw] = top;
      if (raw === "[]") result[key] = [];
      else if (raw.startsWith("[") && raw.endsWith("]")) result[key] = raw.slice(1, -1).split(",").map((item) => item.trim().replace(/^"|"$/g, "")).filter(Boolean);
      else result[key] = raw.replace(/^"|"$/g, "");
      if (raw === "") {
        result[key] = [];
        currentList = key;
      }
      continue;
    }
    const item = line.match(/^\s*-\s+type:\s*"?([^"\n]+)"?$/);
    if (item && currentList) {
      currentItem = { type: item[1] };
      (result[currentList] as Record<string, string>[]).push(currentItem);
      continue;
    }
    const prop = line.match(/^\s+([a-z_]+):\s*"?([^"\n]+)"?$/);
    if (prop && currentItem) currentItem[prop[1]] = prop[2];
  }
  return result;
}

export function findMarkdownFiles(root: string): string[] {
  if (!existsSync(root)) return [];
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir)) {
      const path = join(dir, entry);
      const stats = statSync(path);
      if (stats.isDirectory()) walk(path);
      else if (path.endsWith(".md")) out.push(path);
    }
  };
  walk(root);
  return out;
}

export function relativeToRoot(root: string, path: string): string {
  return relative(root, path).replaceAll("\\", "/");
}

export function printJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}
