// Read-only readers and log parsers for the pipeline job board.
//
// Every source here is optional by design. A lane that is not installed, a log that was never
// written, a task folder that does not exist yet all resolve to null (rendered as "n/a") instead
// of throwing, because the board is needed most when the pipeline is broken.
//
// Nothing in this file writes. The only write in the whole board is the finished HTML page.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, join } from "node:path";

export const STATUSES = ["queue", "active", "review", "blocked", "done"];

// Same thresholds the night watch uses (pipeline/MONITOR.md), so the board never cries wolf
// about a lane the monitor would call healthy.
export const STALL_MIN = 45; // a lane with work waiting and no log line for this long is stuck
export const ACTIVE_TIMEOUT_MIN = 70; // the runner gives up after 60; longer means the runner died
export const STALE_BOARD_MIN = 3; // the board is regenerated every minute; 3 = regeneration stopped
export const PROBE_TIMEOUT_MS = 10_000;

// Lanes, agents, harnesses and branches, mirroring run.ps1's lane table. Lane order is the
// reading order on the page (game code first, art last).
export const TASK_LANES = [
  {
    id: "card",
    label: "Card",
    agent: "builder",
    rules: "BUILDER.md",
    harness: "opencode",
    versionCommand: "opencode",
    branch: "pipeline",
    tasksDir: "tasks",
    logName: "runner.log",
    cooldownTag: "",
  },
  {
    id: "motion",
    label: "Motion",
    agent: "animator",
    rules: "ANIMATOR.md",
    harness: "opencode",
    versionCommand: "opencode",
    branch: "motion",
    tasksDir: "tasks-motion",
    logName: "runner-motion.log",
    cooldownTag: "-motion",
  },
  {
    id: "design",
    label: "Design",
    agent: "designer",
    rules: "DESIGNER.md",
    harness: "opencode",
    versionCommand: "opencode",
    branch: "design",
    tasksDir: "tasks-design",
    logName: "runner-design.log",
    cooldownTag: "-design",
  },
  {
    id: "art",
    label: "Art",
    agent: "artist",
    rules: "ARTIST.md (image repo)",
    harness: "opencode",
    versionCommand: "opencode",
    branch: null, // the art lane lives in its own repo, so there is no branch count to show
    tasksDir: "tasks-art",
    logName: "runner-art.log",
    cooldownTag: "-art",
  },
];

// Every worker gets a card, including the two that are not task lanes.
export const EXTRA_WORKERS = [
  {
    id: "monitor",
    label: "Monitor",
    agent: "monitor",
    rules: "MONITOR.md",
    harness: "opencode",
    versionCommand: "opencode",
    branch: null,
    tasksDir: null,
    logName: "monitor.log",
  },
  {
    id: "freebuff",
    label: "Freebuff",
    agent: "freebuff",
    rules: "FREEBUFF_PROMPT.md",
    harness: "Freebuff CLI",
    versionCommand: "freebuff",
    branch: "freebuff",
    tasksDir: null,
    logName: null,
  },
];

export const MODE_FLAGS = ["FREE_ONLY", "AUTO_MERGE", "STOP", "STOP_NUDGE"];

// --------------------------------------------------------------------------- safe fs access

export function tryRead(path) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

export function tryStat(path) {
  try {
    return statSync(path);
  } catch {
    return null;
  }
}

export function tryList(path) {
  try {
    return readdirSync(path, { withFileTypes: true });
  } catch {
    return null;
  }
}

export function isDir(path) {
  return tryStat(path)?.isDirectory() === true;
}

export function ageMinutes(timestampMs, now) {
  if (typeof timestampMs !== "number" || !Number.isFinite(timestampMs)) return null;
  return Math.max(0, Math.round((now - timestampMs) / 60000));
}

// --------------------------------------------------------------------------- task files

// Task ids live in the file name: T-008-shader-holo.md -> T-008.
export function taskIdOf(fileName) {
  return basename(fileName, ".md").split("-").slice(0, 2).join("-");
}

// The first "# " heading is the goal line. Task ids are shown on their own, so a heading that
// repeats the id ("# T-008: holo variants") is shortened to "holo variants". Task files are written
// by agents, so the title is treated as hostile text everywhere it is shown (see render.mjs).
export function taskTitleOf(fileName, text) {
  const heading = /^#\s+(.+?)\s*$/m.exec(text ?? "");
  const raw = heading === null ? fileSlug(fileName) : heading[1];
  const id = taskIdOf(fileName);
  return raw.startsWith(`${id}:`) ? raw.slice(id.length + 1).trim() || raw : raw;
}

function fileSlug(fileName) {
  const stem = basename(fileName, ".md");
  const slug = stem.replace(/^[A-Za-z]+-\d+-?/, "").replace(/-/g, " ").trim();
  return slug.length > 0 ? slug : stem;
}

export function blockedReasonOf(text) {
  const matches = [...String(text ?? "").matchAll(/^Blocked:\s*(.+?)\s*$/gm)];
  return matches.length > 0 ? matches[matches.length - 1][1] : null;
}

// null means "this lane's queue folder does not exist at all", which the page shows as n/a.
export function listTasks(dir, now) {
  const entries = tryList(dir);
  if (entries === null) return null;
  const tasks = [];
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".md")) continue;
    const full = join(dir, entry.name);
    const text = tryRead(full);
    const info = tryStat(full);
    tasks.push({
      id: taskIdOf(entry.name),
      file: entry.name,
      title: taskTitleOf(entry.name, text),
      blockedReason: blockedReasonOf(text),
      ageMin: info ? ageMinutes(info.mtimeMs, now) : null,
      mtimeMs: info ? info.mtimeMs : null,
    });
  }
  tasks.sort((a, b) => a.file.localeCompare(b.file));
  return tasks;
}

// --------------------------------------------------------------------------- runner logs

// Get-Date -Format 'yyyy-MM-dd HH:mm:ss', local time, like every line in logs/runner*.log.
const STAMP = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\s+(.*)$/;
// The monitor log stamps its model on a "====" header instead of an attempt line.
const MONITOR_HEAD = /^====\s+(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})\s+(\S+)\s*$/;
const ATTEMPT = /^(\S+)\s+attempt\s+(\d+)\s+on\s+(\S+)$/;
const STARTED = /^(\S+)\s+started from\s+(\S+)$/;
const FALLBACK = /falling back to\s+(\S+)/;
const RESULT =
  /(VERIFIED -> review|FAILED -> block|failed verification|auto-merged into main|auto-merge into main CONFLICTED|waiting in review|recovered from interrupted run|timed out)/;

function localStamp(y, mo, d, h, mi, s) {
  const ms = new Date(y, mo - 1, d, h, mi, s).getTime();
  return Number.isFinite(ms) ? ms : null;
}

export function parseLogLine(line) {
  const match = STAMP.exec(String(line ?? "").trim());
  if (!match) return null;
  return {
    ms: localStamp(...match.slice(1, 7).map(Number)),
    message: match[7],
  };
}

function setModel(log, raw) {
  if (typeof raw !== "string" || raw.length === 0) return;
  log.altModel = raw.startsWith("alt|");
  log.model = raw.replace(/^alt\|/, "");
}

// The newest stamp seen anywhere in the file: the board's stall rules are about "no new line".
function bumpLast(log, ms) {
  if (ms === null || !Number.isFinite(ms)) return;
  log.lastMs = log.lastMs === null ? ms : Math.max(log.lastMs, ms);
}

export function parseRunnerLog(text) {
  if (text === null || text === undefined) return null;
  const log = {
    lines: 0,
    lastMs: null,
    model: null,
    altModel: false,
    started: null,
    attempt: null,
    result: null,
    fallbackPending: null,
  };
  for (const raw of text.split(/\r?\n/)) {
    const trimmed = raw.trim();
    if (trimmed.length === 0) continue;

    const head = MONITOR_HEAD.exec(trimmed);
    if (head) {
      log.lines += 1;
      bumpLast(log, localStamp(...head.slice(1, 6).map(Number), 0));
      setModel(log, head[6]);
      continue;
    }

    const entry = parseLogLine(trimmed);
    if (entry === null) continue;
    log.lines += 1;
    bumpLast(log, entry.ms);
    const message = entry.message;

    const attempt = ATTEMPT.exec(message);
    if (attempt) {
      setModel(log, attempt[3]);
      log.attempt = { id: attempt[1], n: Number(attempt[2]) };
      continue;
    }

    const started = STARTED.exec(message);
    if (started) {
      log.started = { id: started[1], base: started[2], at: entry.ms };
      continue;
    }

    const fallback = FALLBACK.exec(message);
    if (fallback) {
      // The lane is between tasks: the offset moved, the NEXT attempt uses this model. The
      // current model stays the last one actually attempted, so the board shows both.
      log.fallbackPending = fallback[1];
      continue;
    }

    if (RESULT.test(message)) log.result = { text: message, at: entry.ms };
  }
  return log;
}

// --------------------------------------------------------------------------- modes

function cooldownActive(until, now) {
  if (typeof until !== "string" || until.trim().length === 0) return true; // unknown expiry: treat as live
  const untilMs = new Date(until).getTime();
  if (!Number.isFinite(untilMs)) return true;
  return untilMs > now;
}

export function readModes(pipelineDir, now) {
  const flags = MODE_FLAGS.map((name) => ({ name, on: existsSync(join(pipelineDir, name)) }));
  const cooldowns = [];
  const offsets = [];
  for (const entry of tryList(pipelineDir) ?? []) {
    if (!entry.isFile()) continue;
    const value = (tryRead(join(pipelineDir, entry.name)) ?? "").trim();
    if (entry.name.startsWith(".cooldown")) {
      cooldowns.push({
        name: entry.name,
        until: value.length > 0 ? value : null,
        active: cooldownActive(value, now),
      });
    } else if (entry.name.startsWith(".model-offset")) {
      offsets.push({ name: entry.name, value: Number.parseInt(value, 10) || 0 });
    }
  }
  cooldowns.sort((a, b) => a.name.localeCompare(b.name));
  offsets.sort((a, b) => a.name.localeCompare(b.name));
  return { flags, cooldowns, offsets };
}

// --------------------------------------------------------------------------- subprocess probes

const SCHEDULED_TASKS_PS =
  "Get-ScheduledTask -TaskName 'Waifu*' | ForEach-Object { " +
  "$i = $_ | Get-ScheduledTaskInfo; " +
  "'{0}|{1}|{2}|{3}' -f $_.TaskName,$_.State,$i.LastRunTime,$i.LastTaskResult }";

// `opencode` and `freebuff` are .cmd shims on Windows, which Node cannot spawn directly, and the
// Task Scheduler query needs PowerShell's own parser: so every probe goes through cmd /c, with a
// timeout so a wedged tool cannot hold the page hostage.
export function makeExec() {
  return function exec(commandLine, timeoutMs = PROBE_TIMEOUT_MS) {
    const isWindows = process.platform === "win32";
    try {
      if (isWindows) {
        return execFileSync(process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", commandLine], {
          encoding: "utf8",
          timeout: timeoutMs,
          windowsHide: true,
          windowsVerbatimArguments: true,
          stdio: ["ignore", "pipe", "ignore"],
        });
      }
      return execFileSync("/bin/sh", ["-c", commandLine], {
        encoding: "utf8",
        timeout: timeoutMs,
        stdio: ["ignore", "pipe", "ignore"],
      });
    } catch {
      return null;
    }
  };
}

function quoteArg(value) {
  return /\s/.test(value) ? `"${value}"` : value;
}

export function readVersions(exec) {
  const versions = {};
  for (const [tool, command] of [
    ["opencode", "opencode --version"],
    ["freebuff", "freebuff --version"],
  ]) {
    const output = exec(command);
    const match = output === null ? null : /(\d+\.\d+\.\d+[^\s]*)/.exec(output);
    versions[tool] = match === null ? null : match[1];
  }
  return versions;
}

// LastTaskResult: 0 = fine, 267011 = "has not run yet", anything else = the task errored.
const TASK_RESULT = {
  0: "ok",
  267011: "never run",
  267009: "running",
  267014: "terminated",
};

export function parseScheduledTasks(output) {
  if (output === null) return null;
  const rows = [];
  for (const raw of output.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.length === 0) continue;
    const [name, state, lastRunTime, lastResult] = line.split("|");
    if (!name) continue;
    const code = Number.parseInt(lastResult ?? "", 10);
    const ok = code === 0 || code === 267009;
    rows.push({
      name: name.trim(),
      state: (state ?? "").trim(),
      lastRunTime: (lastRunTime ?? "").trim(),
      lastResult: Number.isFinite(code) ? code : null,
      status: TASK_RESULT[code] ?? (Number.isFinite(code) ? `error ${code}` : "unknown"),
      ok,
    });
  }
  return rows;
}

export function readScheduledTasks(exec) {
  return parseScheduledTasks(
    exec(`powershell -NoProfile -Command "${SCHEDULED_TASKS_PS}"`),
  );
}

// --------------------------------------------------------------------------- git

export function parseMainCommits(output) {
  if (output === null) return null;
  const lines = output.split(/\r?\n/).map((line) => line.trim());
  return lines.filter((line) => line.length > 0).map((line) => {
    const at = line.indexOf(" ");
    return at < 0 ? { sha: line, text: "" } : { sha: line.slice(0, at), text: line.slice(at + 1) };
  });
}

export function readGit(root, exec) {
  const quoted = quoteArg(root);
  const commits = parseMainCommits(exec(`git -C ${quoted} log --oneline -8 main`));
  const branches = {};
  for (const branch of ["pipeline", "motion", "design", "freebuff"]) {
    const output = exec(`git -C ${quoted} rev-list --count main..${branch}`);
    const count = output === null ? null : Number.parseInt(output.trim(), 10);
    branches[branch] = Number.isFinite(count) ? count : null;
  }
  return { commits, branches };
}

// --------------------------------------------------------------------------- freebuff

export function lastLines(text, count) {
  if (text === null || text === undefined) return null;
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  return lines.slice(Math.max(0, lines.length - count));
}

// The monitor report opens with its time and one line per lane, so the head is what the board shows.
export function firstLines(text, count) {
  if (text === null || text === undefined) return null;
  return text.split(/\r?\n/).filter((line) => line.trim().length > 0).slice(0, count);
}

// The first markdown table of a sweep report (check | screen | severity | result).
export function firstTable(text) {
  if (text === null || text === undefined) return null;
  const rows = [];
  let started = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("|")) {
      rows.push(line);
      started = true;
      continue;
    }
    if (started && line.length > 0) break;
    if (!started && line.length > 0) continue;
  }
  return rows.length > 0 ? rows : null;
}

// Sorted names of the files in dir matching pattern (e.g. sweep-*.md). [] when dir is absent.
export function listMatching(dir, pattern) {
  const entries = tryList(dir);
  if (entries === null) return [];
  const regex = new RegExp(pattern);
  return entries
    .filter((entry) => entry.isFile() && regex.test(entry.name))
    .map((entry) => entry.name)
    .sort();
}

// sweep-9.md is newer than sweep-12.md, so plain name order is wrong: pick the highest number.
export function newestSweep(names) {
  let newest = null;
  let newestNumber = -1;
  for (const name of names) {
    const match = /^sweep-(\d+)/.exec(name);
    const number = match === null ? -1 : Number(match[1]);
    if (newest === null || number > newestNumber || (number === newestNumber && name > newest)) {
      newest = name;
      newestNumber = number;
    }
  }
  return newest;
}