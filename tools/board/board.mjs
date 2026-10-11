// Live job board for the whole overnight pipeline: one HTML page with every lane, worker,
// incident and scheduled task on it.
//
//   node tools/board/board.mjs [--root "E:\AI\Waifu Card Game"] [--out <root>/pipeline/board.html] [--json]
//
// Plain Node, standard library only, no model and no tokens: pipeline/board_run.ps1 runs this
// every minute. READ-ONLY except for the --out page. Every source is optional, so the board still
// renders (full of "n/a") when a lane, a log or the whole pipeline folder is missing.
//
// Tests inject the clock and the subprocess runner (buildModel(root, { now, exec })), so no test
// ever spawns git or PowerShell, and nothing here reaches the network.

import { mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { renderBoard } from "./render.mjs";
import {
  ACTIVE_TIMEOUT_MIN,
  EXTRA_WORKERS,
  STATUSES,
  STALE_BOARD_MIN,
  STALL_MIN,
  TASK_LANES,
  ageMinutes,
  RENDER_STATE_PATH,
  firstLines,
  firstTable,
  isDir,
  lastLines,
  listMatching,
  listTasks,
  makeExec,
  newestSweep,
  parseRunnerLog,
  readAgentRegistry,
  readGenerationJobs,
  readGit,
  readModes,
  readScheduledTasks,
  readVersions,
  tryRead,
  tryStat,
} from "./sources.mjs";

const DEFAULT_ROOT = process.env.WAIFU_PIPELINE_ROOT ?? "E:\\AI\\Waifu Card Game";
const MAX_BLOCKED_PER_LANE = 3; // a broken lane must not push every other lane off the page
const MAX_INCIDENTS = 12;

// --------------------------------------------------------------------------- lanes

// null means "this lane is not installed": no queue folder at all. Inside an installed lane a
// missing status folder is simply empty, so one half-created lane cannot crash the page.
function columnsFor(tasksDir, now) {
  if (!isDir(tasksDir)) return null;
  const columns = {};
  for (const status of STATUSES) {
    const tasks = listTasks(join(tasksDir, status), now) ?? [];
    columns[status] = tasks.map((task) => ({ ...task, status }));
  }
  return columns;
}

function columnCount(columns, status) {
  const tasks = columns === null ? null : columns[status];
  return tasks === null ? null : tasks.length;
}

// Health is deliberately coarse (four words) so it reads on a phone at a glance:
//   BLOCKED  a task sits in blocked/ and only a human can move it on
//   COOLDOWN the lane is backing off after a provider/quota error
//   STALLED  work is waiting but nothing has touched the lane for 45 min (or a task runs too long)
//   OK       anything else
function laneHealth(columns, log, cooldown, now) {
  if (columns !== null && columns.blocked.length > 0) return "BLOCKED";
  if (cooldown.active) return "COOLDOWN";
  const active = columns === null ? [] : columns.active;
  const running = active.find((task) => log?.started?.id === task.id) ?? active[0];
  if (running?.mtimeMs != null && ageMinutes(running.mtimeMs, now) > ACTIVE_TIMEOUT_MIN) {
    return "STALLED";
  }
  const queue = columnCount(columns, "queue");
  const logAge = log?.lastMs == null ? null : ageMinutes(log.lastMs, now);
  if (queue !== null && queue > 0 && (logAge === null || logAge > STALL_MIN)) return "STALLED";
  return "OK";
}

function laneNote(columns, log, cooldown) {
  if (log === null) return "no runner log yet";
  if (columns === null) return "no task folder yet";
  if (cooldown.active) return "backing off after a provider error";
  if (log.fallbackPending === null) return null;
  // The "alt|" prefix is the runner's internal marker; the page says what it means.
  const pending = log.fallbackPending;
  return `next attempt falls back to ${pending.replace(/^alt\|/, "")}${
    pending.startsWith("alt|") ? " (second account)" : ""
  }`;
}

function buildLane(lane, pipelineDir, versions, branches, cooldowns, now) {
  const columns = columnsFor(join(pipelineDir, lane.tasksDir ?? ""), now);
  const log =
    lane.logName === null
      ? null
      : parseRunnerLog(tryRead(join(pipelineDir, "logs", lane.logName)));
  const cooldown = cooldowns.find((entry) => entry.name === `.cooldown${lane.cooldownTag ?? ""}`) ?? {
    name: `.cooldown${lane.cooldownTag ?? ""}`,
    active: false,
    until: null,
  };
  const active = columns === null || columns.active.length === 0 ? [] : columns.active;
  const running = active.find((task) => log?.started?.id === task.id) ?? active[0] ?? null;

  return {
    id: lane.id,
    label: lane.label,
    heading: `${lane.label} lane`,
    agent: lane.agent,
    rules: lane.rules,
    harness: lane.harness,
    version: versions[lane.versionCommand] ?? null,
    branch: lane.branch,
    logName: lane.logName,
    model: log?.model ?? null,
    altModel: log?.altModel ?? false,
    task: running === null ? null : { id: running.id, title: running.title },
    // Elapsed comes from the runner log's "started from" line, not from the task file's mtime: the
    // runner appends result blocks to that file and would reset a mtime-based timer.
    elapsedMin:
      log?.started?.at == null ? (running?.ageMin ?? null) : ageMinutes(log.started.at, now),
    lastResult: log?.result?.text ?? null,
    queueDepth: columnCount(columns, "queue"),
    waitingToMerge: lane.branch === null ? null : (branches[lane.branch] ?? null),
    logAgeMin: log?.lastMs == null ? null : ageMinutes(log.lastMs, now),
    health: laneHealth(columns, log, cooldown, now),
    note: laneNote(columns, log, cooldown),
    columns,
    log,
  };
}

function countTasks(lanes) {
  const counts = { queue: 0, active: 0, review: 0, blocked: 0, done: 0, total: 0 };
  for (const lane of lanes) {
    if (lane.columns === null) continue;
    for (const status of STATUSES) counts[status] += lane.columns[status].length;
    counts.total += STATUSES.reduce((sum, status) => sum + lane.columns[status].length, 0);
  }
  return counts;
}

// --------------------------------------------------------------------------- monitor

function buildMonitor(pipelineDir, now) {
  const reportPath = join(pipelineDir, "MONITOR_REPORT.md");
  const logPath = join(pipelineDir, "logs", "monitor.log");
  const report = tryRead(reportPath);
  const logText = tryRead(logPath);
  if (report === null && logText === null) return null;
  const reportInfo = tryStat(reportPath);
  const log = parseRunnerLog(logText);
  const logAgeMin = log?.lastMs == null ? null : ageMinutes(log.lastMs, now);
  return {
    reportTime:
      reportInfo === null
        ? null
        : new Date(reportInfo.mtimeMs).toLocaleString("en-GB", { hour12: false }),
    reportAgeMin: reportInfo === null ? null : ageMinutes(reportInfo.mtimeMs, now),
    reportLines: firstLines(report, 15),
    logLines: log === null ? null : log.lines,
    logAgeMin,
    logTail: lastLines(logText, 10),
    model: log?.model ?? null,
    altModel: log?.altModel ?? false,
    stalled: logAgeMin !== null && logAgeMin > STALL_MIN,
  };
}

function monitorWorker(monitor, versions) {
  const spec = EXTRA_WORKERS[0];
  return {
    id: spec.id,
    label: spec.label,
    heading: spec.label,
    agent: spec.agent,
    rules: spec.rules,
    harness: spec.harness,
    version: versions[spec.versionCommand] ?? null,
    branch: null,
    logName: spec.logName,
    model: monitor?.model ?? null,
    altModel: monitor?.altModel ?? false,
    task: monitor === null ? null : { id: "", title: "monitoring pass" },
    elapsedMin: monitor?.logAgeMin ?? null,
    lastResult: monitor?.logTail?.[monitor.logTail.length - 1] ?? null,
    queueDepth: null,
    waitingToMerge: null,
    logAgeMin: monitor?.logAgeMin ?? null,
    health: monitor === null ? "OK" : monitor.stalled ? "STALLED" : "OK",
    note: monitor === null ? "no monitor report or log yet" : null,
    columns: null,
    log: null,
  };
}

// --------------------------------------------------------------------------- freebuff

function buildFreebuff(pipelineDir, now) {
  const dir = join(pipelineDir, "freebuff");
  const logPath = join(dir, "LOG.md");
  const logText = tryRead(logPath);
  const logInfo = tryStat(logPath);
  const nudgePath = join(pipelineDir, "logs", "nudge.log");
  const nudgeText = tryRead(nudgePath);
  const sweeps = listMatching(dir, "^sweep-.*\\.md$");
  const newest = newestSweep(sweeps);
  const sweepPath = newest === null ? null : join(dir, newest);
  if (logText === null && nudgeText === null && sweepPath === null) return null;
  const logAgeMin = logInfo === null ? null : ageMinutes(logInfo.mtimeMs, now);
  return {
    logAgeMin,
    logTail: lastLines(logText, 10),
    // The same 45 min rule the night watch uses: no new line means Freebuff is sitting at a prompt.
    stalled: logAgeMin === null || logAgeMin > STALL_MIN,
    sweepFile: sweepPath,
    sweepCount: sweeps.length,
    sweepTable: firstTable(sweepPath === null ? null : tryRead(sweepPath)),
    nudgeCount: nudgeText === null ? null : countLines(nudgeText),
    nudgeTail: lastLines(nudgeText, 5),
  };
}

function countLines(text) {
  return String(text ?? "")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0).length;
}

function freebuffWorker(freebuff, versions, branches, now) {
  const spec = EXTRA_WORKERS[1];
  const sweep = freebuff?.sweepFile ?? null;
  const sweepInfo = sweep === null ? null : tryStat(sweep);
  return {
    id: spec.id,
    label: spec.label,
    heading: spec.label,
    agent: spec.agent,
    rules: spec.rules,
    harness: spec.harness,
    version: versions[spec.versionCommand] ?? null,
    branch: spec.branch,
    logName: "freebuff/LOG.md",
    model: null, // Freebuff is driven from its own window; the prompt file names no model per run
    altModel: false,
    task: sweep === null ? null : { id: "", title: basename(sweep) },
    elapsedMin: sweepInfo === null ? null : ageMinutes(sweepInfo.mtimeMs, now),
    lastResult: freebuff?.logTail?.[freebuff.logTail.length - 1] ?? null,
    queueDepth: null,
    waitingToMerge: branches[spec.branch] ?? null,
    logAgeMin: freebuff?.logAgeMin ?? null,
    health: freebuff === null ? "OK" : freebuff.stalled ? "STALLED" : "OK",
    note: freebuff === null ? "no freebuff/LOG.md yet" : null,
    columns: null,
    log: null,
  };
}

// --------------------------------------------------------------------------- incidents

function collectIncidents({ modes, lanes, monitor, freebuff, scheduledTasks, agents }) {
  const incidents = [];
  // Only the flags that stop work are incidents. FREE_ONLY and AUTO_MERGE are deliberate modes and
  // already have their own chips in the modes strip.
  for (const flag of modes.flags) {
    if (!flag.on) continue;
    if (flag.name === "STOP") incidents.push("every lane paused (pipeline/STOP)");
    if (flag.name === "STOP_NUDGE") incidents.push("Freebuff nudges paused (pipeline/STOP_NUDGE)");
  }
  for (const cooldown of modes.cooldowns) {
    if (!cooldown.active) continue;
    incidents.push(
      cooldown.until === null
        ? `${cooldown.name}: lane cooling down`
        : `${cooldown.name}: cooling down until ${cooldown.until}`,
    );
  }
  for (const lane of lanes) {
    if (lane.health === "STALLED") {
      const queue = lane.queueDepth === null ? 0 : lane.queueDepth;
      incidents.push(
        `${lane.label}: STALLED (${lane.logAgeMin ?? "?"} min quiet, ${queue} queued)`,
      );
    }
    const blocked = lane.columns?.blocked ?? [];
    for (const task of blocked.slice(0, MAX_BLOCKED_PER_LANE)) {
      incidents.push(
        `${lane.label}: ${task.id} blocked - ${task.blockedReason ?? task.title}`,
      );
    }
    if (blocked.length > MAX_BLOCKED_PER_LANE) {
      incidents.push(`${lane.label}: ${blocked.length - MAX_BLOCKED_PER_LANE} more blocked`);
    }
  }
  if (monitor?.stalled) {
    incidents.push(`monitor: no pass for ${monitor.logAgeMin ?? "?"} min`);
  }
  if (freebuff?.stalled) {
    incidents.push(
      `freebuff: LOG.md quiet for ${freebuff.logAgeMin ?? "?"} min (probably at a prompt)`,
    );
  }
  for (const task of scheduledTasks ?? []) {
    if (task.ok || task.lastResult === 267011) continue;
    incidents.push(`scheduled task ${task.name}: ${task.status}`);
  }
  for (const agent of agents?.agents ?? []) {
    const label = `agent ${agent.id}${agent.task ? ` (${agent.task})` : ""}`;
    if (agent.stale) incidents.push(`${label}: stale, no update for ${agent.lastUpdateAgeMin} min`);
    else if (agent.status === "failed") incidents.push(`${label}: failed - ${agent.error ?? "no error recorded"}`);
    else if (agent.status === "blocked") incidents.push(`${label}: blocked - ${agent.error ?? agent.summary ?? "no reason recorded"}`);
  }
  if (incidents.length <= MAX_INCIDENTS) return incidents;
  return [...incidents.slice(0, MAX_INCIDENTS), `${incidents.length - MAX_INCIDENTS} more`];
}

// --------------------------------------------------------------------------- model

export function buildModel(root, options = {}) {
  const now = options.now ?? Date.now();
  const exec = options.exec ?? makeExec();
  const pipelineDir = join(root, "pipeline");
  const versions = readVersions(exec);
  const modes = readModes(pipelineDir, now);
  const git = readGit(root, exec);
  const scheduledTasks = readScheduledTasks(exec);

  const lanes = TASK_LANES.map((lane) =>
    buildLane(lane, pipelineDir, versions, git.branches, modes.cooldowns, now),
  );
  const monitor = buildMonitor(pipelineDir, now);
  const freebuff = buildFreebuff(pipelineDir, now);
  const agents = readAgentRegistry(join(pipelineDir, "agents", "registry.jsonl"), now);
  // options.renderStatePath lets tests point at a fixture; the real path lives in the image repo.
  const generationJobs = readGenerationJobs(options.renderStatePath ?? RENDER_STATE_PATH, now);

  return {
    generatedMs: now,
    staleAfterMin: STALE_BOARD_MIN,
    root,
    versions,
    modes,
    counts: countTasks(lanes),
    incidents: collectIncidents({ modes, lanes, monitor, freebuff, scheduledTasks, agents }),
    workers: [
      ...lanes,
      monitorWorker(monitor, versions),
      freebuffWorker(freebuff, versions, git.branches, now),
    ],
    lanes,
    monitor,
    freebuff,
    scheduledTasks,
    agents,
    generationJobs,
    mainCommits: git.commits,
  };
}

// --------------------------------------------------------------------------- CLI

export function parseArgs(argv) {
  const options = { root: DEFAULT_ROOT, out: null, json: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = (name) => {
      const at = arg.indexOf("=");
      if (at > 0) return arg.slice(at + 1);
      i += 1;
      if (i >= argv.length) throw new Error(`${name} needs a value`);
      return argv[i];
    };
    if (arg === "--json") options.json = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else if (arg === "--root" || arg.startsWith("--root=")) options.root = value("--root");
    else if (arg === "--out" || arg.startsWith("--out=")) options.out = value("--out");
    else throw new Error(`unknown argument: ${arg}`);
  }
  options.root = resolve(options.root);
  options.out =
    options.out === null ? join(options.root, "pipeline", "board.html") : resolve(options.out);
  return options;
}

const USAGE = `usage: node tools/board/board.mjs [--root "<pipeline repo>"] [--out <board.html>] [--json]

  --root   pipeline checkout that holds pipeline/ (default: $WAIFU_PIPELINE_ROOT or
           "${DEFAULT_ROOT}")
  --out    where to write the page (default: <root>/pipeline/board.html)
  --json   print the board model as JSON instead of writing the page`;

export function main(argv, out = console.log, err = console.error, options = {}) {
  let optionsParsed;
  try {
    optionsParsed = parseArgs(argv);
  } catch (error) {
    err(`board: ${error.message}`);
    err(USAGE);
    return 2;
  }
  if (optionsParsed.help) {
    out(USAGE);
    return 0;
  }

  // options.exec lets a test drive main() with a stub probe runner; the CLI always shells out.
  const model = buildModel(optionsParsed.root, {
    now: options.now,
    exec: options.exec,
    renderStatePath: options.renderStatePath,
  });
  if (optionsParsed.json) {
    out(JSON.stringify(model, null, 2));
    return 0;
  }
  try {
    mkdirSync(dirname(optionsParsed.out), { recursive: true });
    writeFileSync(optionsParsed.out, renderBoard(model), "utf8");
  } catch (error) {
    err(`board: could not write ${optionsParsed.out}: ${error.message}`);
    return 1;
  }
  out(`board: wrote ${optionsParsed.out}`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) process.exit(main(process.argv.slice(2)));