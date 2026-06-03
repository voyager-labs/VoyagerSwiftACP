import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const KNOWLEDGE_ROOT = ".sisyphus/knowledge";
const MAX_SUMMARY_CHARS = 1200;
const MAX_STRING_CHARS = 500;

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function safeFilename(value) {
  return value
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "unknown-session";
}

function safeString(value, max = MAX_STRING_CHARS) {
  if (typeof value !== "string") return value;
  return value
    .replace(/sk-[A-Za-z0-9_-]+/g, "[REDACTED_API_KEY]")
    .replace(/(api[_-]?key|token|secret|password)([\s:=]+)([^\s,}\]]+)/gi, "$1$2[REDACTED]")
    .slice(0, max);
}

function sanitize(value, depth = 0) {
  if (depth > 4) return "[TRUNCATED_DEPTH]";
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return safeString(value);
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.slice(0, 20).map((item) => sanitize(item, depth + 1));
  if (typeof value === "object") {
    const output = {};
    for (const [key, child] of Object.entries(value).slice(0, 40)) {
      output[key] = /secret|password|token|api[_-]?key/i.test(key) ? "[REDACTED]" : sanitize(child, depth + 1);
    }
    return output;
  }
  return String(value);
}

function eventName(event) {
  if (!event || typeof event !== "object") return "unknown";
  return event.type || event.name || event.event || event.kind || "unknown";
}

function sessionId(event) {
  const candidates = [
    event?.sessionID,
    event?.sessionId,
    event?.session?.id,
    event?.properties?.sessionID,
    event?.properties?.sessionId,
    event?.properties?.session?.id
  ];
  return candidates.find((candidate) => typeof candidate === "string" && candidate.length > 0) || "unknown-session";
}

function isCandidateEvent(name) {
  return [
    "message.updated",
    "message.part.updated",
    "session.compacted",
    "session.idle",
    "session.updated",
    "todo.updated",
    "file.edited",
    "tool.execute.after"
  ].includes(name);
}

function shouldSkipEvent(event) {
  const part = event?.properties?.part ?? event?.part;
  if (part?.type === "reasoning") return true;
  if (part?.metadata?.openai?.reasoningEncryptedContent) return true;
  return false;
}

function summarize(event) {
  const text = JSON.stringify(sanitize(event));
  return text.length > MAX_SUMMARY_CHARS ? `${text.slice(0, MAX_SUMMARY_CHARS)}…` : text;
}

function appendJsonl(path, payload) {
  appendFileSync(path, `${JSON.stringify(payload)}\n`);
}

function ensureReadme() {
  const path = join(KNOWLEDGE_ROOT, "README.md");
  if (existsSync(path)) return;
  ensureDir(KNOWLEDGE_ROOT);
  appendFileSync(path, "# Sisyphus Knowledge\n\nThis directory is local runtime state for sisyphus-wiki. Do not commit it unless explicitly exported.\n");
}

function appendSessionEvent(event) {
  if (shouldSkipEvent(event)) return;
  const name = eventName(event);
  const sid = sessionId(event);
  const ts = new Date().toISOString();
  const payload = {
    ts,
    event: name,
    session_id: sid,
    summary: summarize(event),
    capture: isCandidateEvent(name) ? "candidate" : "observed"
  };

  const sessionsDir = join(KNOWLEDGE_ROOT, "sessions");
  ensureDir(sessionsDir);
  appendJsonl(join(sessionsDir, `${safeFilename(sid)}.jsonl`), payload);

  if (isCandidateEvent(name)) {
    const inbox = join(KNOWLEDGE_ROOT, "inbox");
    ensureDir(inbox);
    appendJsonl(join(inbox, "pending-extractions.jsonl"), payload);
  }
}

export const SisyphusWikiPlugin = async () => {
  ensureReadme();
  return {
    event: async ({ event }) => {
      try {
        appendSessionEvent(event);
      } catch (error) {
        const errorsDir = join(KNOWLEDGE_ROOT, "errors");
        ensureDir(errorsDir);
        appendJsonl(join(errorsDir, "plugin-errors.jsonl"), {
          ts: new Date().toISOString(),
          error: error instanceof Error ? error.message : String(error)
        });
      }
    },
    experimental: {
      chat: {
        system: {
          transform: async ({ system }) => {
            const reminder = "Project-local sisyphus-wiki capture is active. Preserve durable decisions, corrections, review learnings, and user preferences under .sisyphus/knowledge when they should survive session boundaries.";
            if (Array.isArray(system)) {
              if (system.some((item) => typeof item === "string" && item.includes("sisyphus-wiki capture is active"))) return system;
              return [...system, reminder];
            }
            if (typeof system === "string") {
              if (system.includes("sisyphus-wiki capture is active")) return system;
              return `${system}\n\n${reminder}`;
            }
            return system;
          }
        }
      }
    }
  };
};

export default SisyphusWikiPlugin;
