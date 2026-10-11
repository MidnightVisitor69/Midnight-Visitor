// Appends one event to the recovery agent registry that the board reads.
//
//   node tools/board/agent.mjs <register|update|heartbeat> <id> [--status s] [--task t] ...
//
// The registry is append-only JSON Lines (<root>/pipeline/agents/registry.jsonl); this is the only
// writer, and it never rewrites or deletes a line. Plain Node, standard library only.

import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { AGENT_EVENTS, AGENT_STATUSES } from "./sources.mjs";

const DEFAULT_ROOT = process.env.WAIFU_PIPELINE_ROOT ?? "E:/AI/Waifu Card Game";
const TEXT_FLAGS = [
  "status", "task", "workstream", "provider", "model", "agent", "repo",
  "branch", "worktree", "summary", "error", "results", "log",
];

// ISO 8601 in local time with the numeric offset (2026-10-11T14:20:00-05:00).
export function localIso(date = new Date()) {
  const pad = (n, width = 2) => String(n).padStart(width, "0");
  const offset = -date.getTimezoneOffset();
  const sign = offset < 0 ? "-" : "+";
  const abs = Math.abs(offset);
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`
  );
}

export function parseAgentArgs(argv) {
  const [event, id, ...rest] = argv;
  if (!AGENT_EVENTS.includes(event)) throw new Error(`first argument must be ${AGENT_EVENTS.join("|")}`);
  if (id === undefined || id.startsWith("--")) throw new Error("second argument must be the agent id");
  const fields = {};
  let root = DEFAULT_ROOT;
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    if (!flag.startsWith("--")) throw new Error(`unexpected argument: ${flag}`);
    const name = flag.slice(2);
    if (i + 1 >= rest.length) throw new Error(`${flag} needs a value`);
    const value = rest[(i += 1)];
    if (name === "root") root = value;
    else if (name === "owns") fields.owns = value.split(",").map((part) => part.trim()).filter(Boolean);
    else if (TEXT_FLAGS.includes(name)) fields[name] = value;
    else throw new Error(`unknown flag: ${flag}`);
  }
  if (fields.status !== undefined && !AGENT_STATUSES.includes(fields.status)) {
    throw new Error(`bad status "${fields.status}" (use ${AGENT_STATUSES.join("|")})`);
  }
  return { event, id, fields, root: resolve(root) };
}

export function main(argv, err = console.error, now = new Date()) {
  let parsed;
  try {
    parsed = parseAgentArgs(argv);
  } catch (error) {
    err(`agent: ${error.message}`);
    err("usage: node tools/board/agent.mjs <register|update|heartbeat> <id> [--status s] [--task t] [--workstream w] [--provider p] [--model m] [--agent a] [--branch b] [--worktree w] [--owns a,b] [--summary s] [--error e] [--results path] [--log path] [--root <root>]");
    return 2;
  }
  const path = join(parsed.root, "pipeline", "agents", "registry.jsonl");
  const line = JSON.stringify({ ts: localIso(now), id: parsed.id, event: parsed.event, ...parsed.fields });
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, `${line}\n`, "utf8");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) process.exit(main(process.argv.slice(2)));
