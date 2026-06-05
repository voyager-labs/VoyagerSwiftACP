import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";

const KNOWLEDGE_ROOT = ".sisyphus/knowledge";
const MAX_TEXT_CHARS = 4000;
const MAX_SUMMARY_CHARS = 1000;
const MAX_STRING_CHARS = 300;

const messageRoles = new Map();
const emittedTextParts = new Set();
const emittedToolStatuses = new Set();

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function safeFilename(value) {
  return value
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120) || "unknown-session";
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
    event?.properties?.session?.id,
    event?.properties?.info?.sessionID,
    event?.properties?.info?.id,
    event?.properties?.part?.sessionID
  ];
  return candidates.find((candidate) => typeof candidate === "string" && candidate.length > 0) || "unknown-session";
}

function messageInfo(event) {
  return event?.properties?.info ?? event?.info;
}

function messagePart(event) {
  return event?.properties?.part ?? event?.part;
}

function rememberMessageRole(event) {
  const info = messageInfo(event);
  if (!info?.id || !info?.role) return;
  messageRoles.set(info.id, info.role);
}

function shouldSkipEvent(event) {
  const part = messagePart(event);
  if (part?.type === "reasoning") return true;
  if (part?.metadata?.openai?.reasoningEncryptedContent) return true;
  return false;
}

function shortHash(value) {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

function truncateText(value, max = MAX_TEXT_CHARS) {
  if (typeof value !== "string") return "";
  const text = safeString(value, max);
  return text.length >= max ? `${text.slice(0, max)}…` : text;
}

function sessionMetadata(event) {
  const info = event?.properties?.info ?? event?.info;
  if (!info?.id) return undefined;
  return {
    id: info.id,
    title: truncateText(info.title ?? "", 240) || undefined,
    slug: info.slug,
    parent_id: info.parentID,
    agent: info.agent,
    model: info.model?.id ?? info.model?.modelID,
    directory: info.directory,
    updated_at: info.time?.updated ? new Date(info.time.updated).toISOString() : undefined
  };
}

function toolSummary(part) {
  const state = part?.state ?? {};
  const input = sanitize(state.input ?? {});
  return {
    tool: part?.tool,
    call_id: part?.callID,
    status: state.status,
    title: truncateText(state.title ?? "", 240) || undefined,
    input,
    output_preview: truncateText(state.output ?? "", MAX_SUMMARY_CHARS) || undefined
  };
}

function todoSummary(event) {
  const todos = event?.properties?.todos ?? event?.todos ?? [];
  if (!Array.isArray(todos)) return undefined;
  return todos.slice(0, 20).map((todo) => ({
    content: truncateText(todo.content ?? "", 240),
    status: todo.status,
    priority: todo.priority
  }));
}

function turnEventFromEvent(event) {
  if (shouldSkipEvent(event)) return undefined;

  const name = eventName(event);
  rememberMessageRole(event);

  if (name === "session.created" || name === "session.updated") {
    const metadata = sessionMetadata(event);
    if (!metadata) return undefined;
    return { event: "turn.session", metadata, capture: "observed" };
  }

  if (name === "todo.updated") {
    const todos = todoSummary(event);
    if (!todos) return undefined;
    return { event: "turn.todo", todos, capture: "observed" };
  }

  if (name !== "message.part.updated") return undefined;

  const part = messagePart(event);
  if (!part) return undefined;

  if (part.type === "text") {
    const text = truncateText(part.text ?? "");
    if (!text.trim()) return undefined;

    const messageId = part.messageID;
    const role = messageRoles.get(messageId) ?? "assistant";
    if (role !== "user" && role !== "assistant") return undefined;
    if (role === "assistant" && !part.time?.end) return undefined;

    const partKey = `${sessionId(event)}:${messageId}:${part.id}`;
    if (emittedTextParts.has(partKey)) return undefined;
    emittedTextParts.add(partKey);

    return {
      event: role === "user" ? "turn.user" : "turn.assistant",
      message_id: messageId,
      part_id: part.id,
      role,
      text,
      text_hash: shortHash(text),
      capture: "candidate"
    };
  }

  if (part.type === "tool") {
    const status = part.state?.status;
    if (status !== "completed" && status !== "error") return undefined;
    const key = `${sessionId(event)}:${part.messageID}:${part.callID}:${status}`;
    if (emittedToolStatuses.has(key)) return undefined;
    emittedToolStatuses.add(key);
    return {
      event: "turn.tool",
      message_id: part.messageID,
      ...toolSummary(part),
      capture: "observed"
    };
  }

  return undefined;
}

function appendJsonl(path, payload) {
  appendFileSync(path, `${JSON.stringify(payload)}\n`);
}

function appendTurnRecord(sessionID, record) {
  if (!sessionID || sessionID === "unknown-session") return;
  const payload = {
    ts: new Date().toISOString(),
    ...record,
    session_id: sessionID
  };

  const sessionsDir = join(KNOWLEDGE_ROOT, "sessions");
  ensureDir(sessionsDir);
  appendJsonl(join(sessionsDir, `${safeFilename(sessionID)}.jsonl`), payload);

  if (payload.capture === "candidate") {
    const inbox = join(KNOWLEDGE_ROOT, "inbox");
    ensureDir(inbox);
    appendJsonl(join(inbox, "pending-extractions.jsonl"), payload);
  }
}

function ensureReadme() {
  const path = join(KNOWLEDGE_ROOT, "README.md");
  if (existsSync(path)) return;
  ensureDir(KNOWLEDGE_ROOT);
  appendFileSync(path, "# Sisyphus Knowledge\n\nThis directory is local runtime state for sisyphus-wiki. Do not commit it unless explicitly exported.\n");
}

function appendSessionEvent(event) {
  const sid = sessionId(event);
  if (sid === "unknown-session") return;

  const turnEvent = turnEventFromEvent(event);
  if (!turnEvent) return;

  appendTurnRecord(sid, {
    ...turnEvent,
    source_event: eventName(event)
  });
}

function textFromParts(parts) {
  if (!Array.isArray(parts)) return "";
  return parts
    .filter((part) => part?.type === "text" && !part?.synthetic && !part?.ignored)
    .map((part) => part.text)
    .filter((text) => typeof text === "string" && text.trim().length > 0)
    .join("\n\n");
}

function appendUserTurn(input, output) {
  const sessionID = input?.sessionID ?? output?.message?.sessionID;
  const messageID = input?.messageID ?? output?.message?.id;
  const text = truncateText(textFromParts(output?.parts));
  if (!sessionID || !messageID || !text.trim()) return;

  const partID = output?.parts?.find((part) => part?.type === "text")?.id;
  const partKey = `${sessionID}:${messageID}:${partID ?? shortHash(text)}:chat.message`;
  if (emittedTextParts.has(partKey)) return;
  emittedTextParts.add(partKey);

  appendTurnRecord(sessionID, {
    event: "turn.user",
    message_id: messageID,
    part_id: partID,
    role: "user",
    agent: input?.agent ?? output?.message?.agent,
    model: input?.model ?? output?.message?.model,
    text,
    text_hash: shortHash(text),
    capture: "candidate",
    source_event: "chat.message"
  });
}

function appendAssistantTurn(input, output) {
  const sessionID = input?.sessionID;
  const messageID = input?.messageID;
  const partID = input?.partID;
  const text = truncateText(output?.text ?? "");
  if (!sessionID || !messageID || !partID || !text.trim()) return;

  const partKey = `${sessionID}:${messageID}:${partID}:experimental.text.complete`;
  if (emittedTextParts.has(partKey)) return;
  emittedTextParts.add(partKey);

  appendTurnRecord(sessionID, {
    event: "turn.assistant",
    message_id: messageID,
    part_id: partID,
    role: "assistant",
    text,
    text_hash: shortHash(text),
    capture: "candidate",
    source_event: "experimental.text.complete"
  });
}

function appendToolTurn(input, output) {
  const sessionID = input?.sessionID;
  const callID = input?.callID;
  if (!sessionID || !callID) return;

  const key = `${sessionID}:${callID}:tool.execute.after`;
  if (emittedToolStatuses.has(key)) return;
  emittedToolStatuses.add(key);

  appendTurnRecord(sessionID, {
    event: "turn.tool",
    tool: input?.tool,
    call_id: callID,
    status: "completed",
    input: sanitize(input?.args ?? {}),
    title: truncateText(output?.title ?? "", 240) || undefined,
    output_preview: truncateText(output?.output ?? "", MAX_SUMMARY_CHARS) || undefined,
    metadata: sanitize(output?.metadata ?? {}),
    capture: "observed",
    source_event: "tool.execute.after"
  });
}

export const SisyphusWikiPlugin = async () => {
  ensureReadme();
  const guarded = (handler) => async (...args) => {
    try {
      await handler(...args);
    } catch (error) {
      const errorsDir = join(KNOWLEDGE_ROOT, "errors");
      ensureDir(errorsDir);
      appendJsonl(join(errorsDir, "plugin-errors.jsonl"), {
        ts: new Date().toISOString(),
        error: error instanceof Error ? error.message : String(error)
      });
    }
  };

  return {
    event: guarded(async ({ event }) => {
      appendSessionEvent(event);
    }),
    "chat.message": guarded(async (input, output) => {
      appendUserTurn(input, output);
    }),
    "tool.execute.after": guarded(async (input, output) => {
      appendToolTurn(input, output);
    }),
    "experimental.text.complete": guarded(async (input, output) => {
      appendAssistantTurn(input, output);
    }),
    "experimental.chat.system.transform": guarded(async (_input, output) => {
      const reminder = "Project-local sisyphus-wiki capture is active. Preserve durable decisions, corrections, review learnings, and user preferences under .sisyphus/knowledge when they should survive session boundaries.";
      if (Array.isArray(output?.system)) {
        if (output.system.some((item) => typeof item === "string" && item.includes("sisyphus-wiki capture is active"))) return;
        output.system.push(reminder);
      }
    })
  };
};

export default SisyphusWikiPlugin;
