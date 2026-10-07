// Tests for tools/board/board.mjs. The fixture pipeline tree is built in a temp dir at runtime,
// and every subprocess probe (opencode --version, freebuff --version, git, Task Scheduler) is
// stubbed, so the suite never runs a command and never touches the real pipeline.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { buildModel, main, parseArgs } from "./board.mjs";
import { esc } from "./render.mjs";
import {
  blockedReasonOf,
  newestSweep,
  parseRunnerLog,
  parseScheduledTasks,
  taskIdOf,
  taskTitleOf,
} from "./sources.mjs";

// Fixed clock so nothing in the assertions depends on when the suite runs: 2026-10-07 05:00:00.
const NOW = new Date(2026, 9, 7, 5, 0, 0).getTime();

const PROBES = {
  "opencode --version": "1.18.32\n",
  "freebuff --version": "0.4.1\n",
  "git -C ROOT rev-list --count main..pipeline": "3\n",
  "git -C ROOT rev-list --count main..motion": "1\n",
  "git -C ROOT rev-list --count main..design": "0\n",
  "git -C ROOT rev-list --count main..freebuff": "7\n",
  "git -C ROOT log --oneline -8 main": "74b0e83 Coordinator playbook\n2cebf94 Merge verified work\n",
};

const SCHEDULED =
  "Waifu Pipeline Runner|Ready|10/7/2026 4:59:27 AM|0\n" +
  "Waifu Monitor|Ready|10/7/2026 4:46:38 AM|0\n" +
  "Waifu Design Lane|Ready|10/7/2026 4:54:02 AM|1\n";

function stubExec(root, extra = {}) {
  const table = new Map(
    Object.entries(PROBES).map(([key, value]) => [
      key.replaceAll("ROOT", root),
      value === null ? null : value,
    ]),
  );
  for (const [key, value] of Object.entries(extra)) {
    table.set(key.replaceAll("ROOT", root), value);
  }
  return (commandLine) => (table.has(commandLine) ? table.get(commandLine) : null);
}

function write(root, relative, contents) {
  const path = join(root, relative);
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, contents, "utf8");
  return path;
}

// Backdate a file that already exists; never write to it.
function touch(root, relative, minutesAgo) {
  const path = join(root, relative);
  const when = (NOW - minutesAgo * 60000) / 1000;
  utimesSync(path, when, when);
  return path;
}

// --------------------------------------------------------------------------- fixtures

// Two lanes (card + motion), three card tasks, one motion task, a log with a model switch and a
// fallback, and an agent-written task title that tries to inject a script tag.
function makeFixture() {
  const root = mkdtempSync(join(tmpdir(), "board-"));
  for (const status of ["queue", "active", "review", "blocked", "done"]) {
    mkdirSync(join(root, "pipeline", "tasks", status), { recursive: true });
    mkdirSync(join(root, "pipeline", "tasks-motion", status), { recursive: true });
  }

  write(root, "pipeline/tasks/queue/T-009-next.md", "# T-009: next thing\n\n## Goal\nmore\n");
  touch(root, "pipeline/tasks/queue/T-009-next.md", 30);
  write(
    root,
    "pipeline/tasks/active/T-008-holo.md",
    "# T-008: holo variants\n\n## Goal\nshaders\n",
  );
  touch(root, "pipeline/tasks/active/T-008-holo.md", 31);
  write(
    root,
    "pipeline/tasks/blocked/T-006-thing.md",
    "# T-006: broken\n\nBlocked: node tests: 2 failed\n",
  );
  touch(root, "pipeline/tasks/blocked/T-006-thing.md", 90);
  write(root, "pipeline/tasks-motion/queue/M-004-pack.md", "# M-004: pack opening\n");
  touch(root, "pipeline/tasks-motion/queue/M-004-pack.md", 5);
  write(root, "pipeline/FREE_ONLY", "");
  write(root, "pipeline/.cooldown-design", "2026-10-07T04:30:00");

  write(
    root,
    "pipeline/logs/runner.log",
    [
      "2026-10-07 04:40:00 T-007 attempt 1 on opencode-go/deepseek-v4.1-flash",
      "2026-10-07 04:41:00 T-006 attempt 1 failed verification",
      "2026-10-07 04:42:00 T-006 FAILED -> blocked (node tests: 2 failed)",
      "2026-10-07 04:45:36 T-008 started from 74b0e83",
      "2026-10-07 04:45:40 T-008 attempt 1 on opencode/space-bunny-free",
      "2026-10-07 04:46:00 T-008 attempt 1 failed verification",
      "2026-10-07 04:46:05 T-008 attempt 2 on opencode-go/kimi-k3",
      "2026-10-07 04:46:20 T-008 hit a provider/quota error on opencode-go/kimi-k3; falling back to alt|opencode-go/deepseek-v4.1-flash",
      "",
    ].join("\n"),
  );
  write(
    root,
    "pipeline/logs/runner-motion.log",
    [
      "2026-10-07 04:30:00 M-003 attempt 1 on alt|opencode/space-bunny-free",
      "2026-10-07 04:31:00 M-003 VERIFIED -> review",
      "2026-10-07 04:33:00 M-003 auto-merged into main",
      "",
    ].join("\n"),
  );

  // Freebuff wrote LOG.md 50 minutes ago: that is a STALL (45 min rule).
  const fbLog = write(
    root,
    "pipeline/freebuff/LOG.md",
    "# Freebuff log\n\n- 2026-10-07 04:05 round 3: 41/43 checks pass, 2 fixes committed\n",
  );
  const fbWhen = (NOW - 50 * 60000) / 1000;
  utimesSync(fbLog, fbWhen, fbWhen);

  write(
    root,
    "pipeline/freebuff/sweep-3.md",
    [
      "# Sweep 3",
      "",
      "| check | screen | severity | result |",
      "|---|---|---|---|",
      "| tap-targets | collection | major | fail |",
      "| scroll-end | pack | minor | pass |",
      "",
      "Details below.",
      "",
    ].join("\n"),
  );
  touch(root, "pipeline/freebuff/sweep-3.md", 12);
  write(
    root,
    "pipeline/freebuff/sweep-12.md",
    "# Sweep 12\n\n| check | screen | severity | result |\n|---|---|---|---|\n| scroll-end | pack | minor | fail |\n",
  );
  touch(root, "pipeline/freebuff/sweep-12.md", 4);
  write(root, "pipeline/logs/nudge.log", "nudge 1\nnudge 2\n");

  write(
    root,
    "pipeline/MONITOR_REPORT.md",
    "# Monitor report\n\nTime: 2026-10-07 04:50\n\n- card: T-008 running\n- Needs the dev: T-006 blocked\n",
  );
  write(
    root,
    "pipeline/logs/monitor.log",
    "==== 2026-10-07 04:45 alt|opencode/space-bunny-free\nmonitor pass done\n",
  );

  return root;
}

function modelOf(root, extra = {}) {
  return buildModel(root, { now: NOW, exec: execOf(root, extra) });
}

// Every probe the board runs, stubbed: nothing in this suite spawns a process.
function execOf(root, extra = {}) {
  const table = new Map(
    Object.entries(PROBES).map(([key, value]) => [key.replaceAll("ROOT", root), value]),
  );
  const scheduled = extra.powershell ?? SCHEDULED;
  return (commandLine) => {
    if (commandLine.startsWith("powershell")) return scheduled;
    return table.has(commandLine) ? table.get(commandLine) : null;
  };
}

// Render the page exactly like the CLI does, with the stub probes.
function htmlOf(root, extra = {}) {
  const out = join(root, "pipeline", "board.html");
  const code = main(["--root", root, "--out", out], () => {}, () => {}, {
    now: NOW,
    exec: execOf(root, extra),
  });
  assert.equal(code, 0);
  return readFileSync(out, "utf8");
}

function jsonOf(root, extra = {}) {
  const lines = [];
  const code = main(["--root", root, "--json"], (line) => lines.push(line), () => {}, {
    now: NOW,
    exec: execOf(root, extra),
  });
  assert.equal(code, 0);
  return lines.join("\n");
}

// --------------------------------------------------------------------------- tests

test("current model per lane is the last attempt, not the fallback line", () => {
  const root = makeFixture();
  const model = modelOf(root);
  const card = model.lanes.find((lane) => lane.id === "card");
  const motion = model.lanes.find((lane) => lane.id === "motion");
  assert.equal(card.model, "opencode-go/kimi-k3");
  assert.equal(card.altModel, false);
  // The "falling back to alt|..." line moved the offset for the NEXT attempt; it must not
  // overwrite the model the lane is on right now.
  assert.equal(card.log.fallbackPending, "alt|opencode-go/deepseek-v4.1-flash");
  // The motion lane's last attempt ran on the second account, and that is flagged as such.
  assert.equal(motion.model, "opencode/space-bunny-free");
  assert.equal(motion.altModel, true);
});

test("a task title drops the id the board already shows beside it", () => {
  assert.equal(taskTitleOf("T-008-holo.md", "# T-008: holo variants\n"), "holo variants");
  assert.equal(taskTitleOf("T-008-holo.md", "# the runner is on fire\n"), "the runner is on fire");
  assert.equal(taskTitleOf("T-008-holo.md", ""), "holo", "falls back to the file-name slug");
  assert.equal(taskTitleOf("T-008-holo.md", null), "holo");
  assert.equal(taskTitleOf("T-008.md", null), "T-008", "a bare id keeps something to show");
  assert.equal(taskIdOf("M-004-pack-opening.md"), "M-004");
  assert.equal(blockedReasonOf("Blocked: first\n\nmore\nBlocked: second\n"), "second");
  assert.equal(blockedReasonOf("no reason here"), null);
});

test("the newest sweep is the highest number, not the last name in order", () => {
  assert.equal(newestSweep(["sweep-3.md", "sweep-12.md", "sweep-9.md"]), "sweep-12.md");
  assert.equal(newestSweep(["sweep-2.md"]), "sweep-2.md");
  assert.equal(newestSweep([]), null);
  assert.equal(newestSweep(["notes.md"]), "notes.md", "a stray file is still usable");
});

test("model switches: the most recent attempt line wins in each lane's own log", () => {
  const log = parseRunnerLog(
    [
      "2026-10-07 01:00:00 T-001 attempt 1 on model/one",
      "2026-10-07 01:10:00 T-001 attempt 2 on model/two",
      "2026-10-07 01:20:00 T-002 attempt 1 on model/three",
      "",
    ].join("\n"),
  );
  assert.equal(log.model, "model/three");
  assert.equal(log.altModel, false);
});

test("elapsed for the active task comes from the runner log's start line", () => {
  const root = makeFixture();
  const model = modelOf(root);
  const card = model.lanes.find((lane) => lane.id === "card");
  // "T-008 started from 74b0e83" at 04:45:36, now is 05:00:00.
  assert.equal(card.task.id, "T-008");
  assert.equal(card.task.title, "holo variants", "the id is shown on its own, not twice");
  assert.equal(card.elapsedMin, 14);
  assert.equal(card.queueDepth, 1);
  assert.equal(card.waitingToMerge, 3);
  assert.equal(card.health, "BLOCKED");
});

test("a lane with queued work and a quiet log is STALLED", () => {
  const root = makeFixture();
  // The motion log's last line is at 04:33 and its queue holds M-004: 27 min, still healthy.
  assert.equal(modelOf(root).lanes.find((lane) => lane.id === "motion").health, "OK");

  const now = new Date(2026, 9, 7, 5, 30, 0).getTime();
  const stale = buildModel(root, { now, exec: execOf(root) });
  assert.equal(stale.lanes.find((lane) => lane.id === "motion").health, "STALLED");
  assert.ok(
    stale.incidents.some((incident) => incident.startsWith("Motion: STALLED")),
    `expected a Motion STALLED incident, got: ${stale.incidents.join(" | ")}`,
  );
});

test("freebuff with a LOG.md 50 minutes old is STALLED", () => {
  const root = makeFixture();
  const model = modelOf(root);
  assert.equal(model.freebuff.stalled, true);
  assert.equal(model.freebuff.logAgeMin, 50);
  const worker = model.workers.find((one) => one.id === "freebuff");
  assert.equal(worker.health, "STALLED");
  assert.equal(worker.waitingToMerge, 7);
  assert.equal(model.freebuff.sweepCount, 2);
  assert.match(model.freebuff.sweepFile, /sweep-12\.md$/, "the newest sweep wins, not the first");
  assert.equal(model.freebuff.nudgeCount, 2);
  assert.deepEqual(model.freebuff.nudgeTail, ["nudge 1", "nudge 2"]);
  assert.deepEqual(model.freebuff.sweepTable, [
    "| check | screen | severity | result |",
    "|---|---|---|---|",
    "| scroll-end | pack | minor | fail |",
  ]);
});

test("freebuff with a fresh LOG.md is not stalled", () => {
  const root = makeFixture();
  const fbLog = join(root, "pipeline", "freebuff", "LOG.md");
  const fresh = (NOW - 5 * 60000) / 1000;
  utimesSync(fbLog, fresh, fresh);
  assert.equal(modelOf(root).freebuff.stalled, false);
});

test("missing sources render n/a instead of crashing", () => {
  const empty = mkdtempSync(join(tmpdir(), "board-empty-"));
  const model = buildModel(empty, { now: NOW, exec: () => null });
  assert.equal(model.lanes.length, 4);
  for (const lane of model.lanes) {
    assert.equal(lane.model, null, lane.id);
    assert.equal(lane.columns, null, lane.id);
    assert.equal(lane.queueDepth, null, lane.id);
    assert.equal(lane.waitingToMerge, null, lane.id);
    assert.equal(lane.task, null, lane.id);
    assert.equal(lane.lastResult, null, lane.id);
    assert.equal(lane.health, "OK");
  }
  assert.equal(model.monitor, null);
  assert.equal(model.freebuff, null);
  assert.equal(model.scheduledTasks, null);
  assert.equal(model.mainCommits, null);
  assert.deepEqual(model.counts, { queue: 0, active: 0, review: 0, blocked: 0, done: 0, total: 0 });

  const html = htmlOf(empty);
  assert.ok(html.includes("n/a"), "the page should show n/a for missing sources");
  assert.ok(html.includes('<meta http-equiv="refresh" content="60">'));
  assert.ok(html.includes(`var generatedAtMs = ${NOW};`));
});

test("a missing lane folder shows n/a in every kanban column while others show counts", () => {
  const root = makeFixture();
  const model = modelOf(root);
  const motion = model.lanes.find((lane) => lane.id === "motion");
  assert.equal(motion.columns.queue.length, 1);
  assert.deepEqual(model.counts, {
    queue: 2,
    active: 1,
    review: 0,
    blocked: 1,
    done: 0,
    total: 4,
  });
  const design = model.lanes.find((lane) => lane.id === "design");
  assert.equal(design.columns, null);
  assert.equal(design.note, "no runner log yet");
});

test("modes: flags, cooldown and model offset are all read from pipeline/", () => {
  const root = makeFixture();
  write(root, "pipeline/.model-offset-motion", "2");
  write(root, "pipeline/AUTO_MERGE", "");
  const modes = modelOf(root).modes;
  assert.equal(modes.flags.find((flag) => flag.name === "FREE_ONLY").on, true);
  assert.equal(modes.flags.find((flag) => flag.name === "AUTO_MERGE").on, true);
  assert.equal(modes.flags.find((flag) => flag.name === "STOP").on, false);
  assert.deepEqual(modes.offsets, [{ name: ".model-offset-motion", value: 2 }]);
  const cooldown = modes.cooldowns.find((entry) => entry.name === ".cooldown-design");
  assert.equal(cooldown.active, false, "the cooldown in the fixture expired at 04:30");
});

test("a live cooldown marks its lane COOLDOWN, an expired one does not", () => {
  const root = makeFixture();
  write(root, "pipeline/.cooldown-motion", "2026-10-07T09:00:00");
  const live = modelOf(root);
  assert.equal(live.lanes.find((lane) => lane.id === "motion").health, "COOLDOWN");
  assert.equal(live.lanes.find((lane) => lane.id === "motion").note, "backing off after a provider error");
  assert.ok(
    live.incidents.some((incident) =>
      incident.includes(".cooldown-motion: cooling down until 2026-10-07T09:00:00"),
    ),
    `incidents were: ${live.incidents.join(" | ")}`,
  );

  const later = buildModel(root, {
    now: new Date(2026, 9, 7, 10, 0, 0).getTime(),
    exec: execOf(root),
  });
  assert.equal(later.modes.cooldowns.find((entry) => entry.name === ".cooldown-motion").active, false);
  // 10:00 is also past the log's last line, so the lane is stalled rather than idle-and-fine.
  assert.equal(later.lanes.find((lane) => lane.id === "motion").health, "STALLED");
  assert.equal(
    later.incidents.some((incident) => incident.includes(".cooldown-motion")),
    false,
    "an expired cooldown is not an incident",
  );
});

test("versions come from the harnesses, once per run", () => {
  const root = makeFixture();
  const calls = [];
  const exec = (commandLine) => {
    calls.push(commandLine);
    return execOf(root)(commandLine);
  };
  const model = buildModel(root, { now: NOW, exec });
  assert.equal(model.versions.opencode, "1.18.32");
  assert.equal(model.versions.freebuff, "0.4.1");
  assert.equal(model.workers.find((worker) => worker.id === "card").version, "1.18.32");
  assert.equal(calls.filter((line) => line === "opencode --version").length, 1);
  assert.equal(calls.filter((line) => line === "freebuff --version").length, 1);
  assert.equal(calls.filter((line) => line.startsWith("git -C")).length, 5);
  assert.equal(calls.filter((line) => line.startsWith("powershell")).length, 1);
});

test("scheduled tasks are parsed into name, state, last run and result", () => {
  const rows = parseScheduledTasks(
    "Waifu Pipeline Runner|Ready|10/7/2026 4:59:27 AM|0\n" +
      "Waifu Monitor|Ready|10/7/2026 4:46:38 AM|0\n" +
      "Waifu Old Job|Ready|11/30/1999 12:00:00 AM|267011\n" +
      "Waifu Design Lane|Ready|10/7/2026 4:54:02 AM|1\n",
  );
  assert.equal(rows.length, 4);
  assert.equal(rows[0].name, "Waifu Pipeline Runner");
  assert.equal(rows[0].ok, true);
  assert.equal(rows[2].status, "never run");
  assert.equal(rows[3].ok, false);
  assert.equal(rows[3].status, "error 1");
  assert.equal(parseScheduledTasks(null), null);
});

test("a failing scheduled task is an incident, a never-run one is not", () => {
  const root = makeFixture();
  const incidents = modelOf(root).incidents;
  assert.ok(
    incidents.some((incident) => incident.includes("Waifu Design Lane: error 1")),
    `expected the failing task in the incidents, got: ${incidents.join(" | ")}`,
  );
  const quiet = buildModel(root, {
    now: NOW,
    exec: execOf(root, { powershell: "Waifu Old Job|Ready|11/30/1999 12:00:00 AM|267011\n" }),
  });
  assert.equal(
    quiet.incidents.some((incident) => incident.includes("Waifu Old Job")),
    false,
  );
});

test("blocked tasks show their Blocked: reason and land in the incidents", () => {
  const root = makeFixture();
  const model = modelOf(root);
  const blocked = model.lanes
    .find((lane) => lane.id === "card")
    .columns.blocked.map((task) => task.blockedReason);
  assert.deepEqual(blocked, ["node tests: 2 failed"]);
  assert.ok(
    model.incidents.includes("Card: T-006 blocked - node tests: 2 failed"),
    `incidents were: ${model.incidents.join(" | ")}`,
  );
});

test("monitor panel carries the report time, its first 15 lines and the log tail", () => {
  const root = makeFixture();
  write(
    root,
    "pipeline/MONITOR_REPORT.md",
    ["# Monitor report", ...Array.from({ length: 40 }, (_, i) => `line ${i + 1}`)].join("\n"),
  );
  const model = modelOf(root);
  assert.equal(model.monitor.reportLines.length, 15);
  assert.equal(model.monitor.reportLines[0], "# Monitor report");
  assert.equal(model.monitor.reportLines[14], "line 14");
  assert.equal(model.monitor.model, "opencode/space-bunny-free");
  assert.equal(model.monitor.altModel, true);
  // The monitor stamps its passes on "====" headers, so its age comes from those, not a runner line.
  assert.equal(model.monitor.logAgeMin, 15);
  assert.equal(model.monitor.stalled, false);
  assert.ok(model.monitor.reportTime !== null);

  // A monitor that has not passed for an hour is STALLED, and says so on the worker card.
  const old = new Date(2026, 9, 7, 6, 0, 0).getTime();
  const stale = buildModel(root, { now: old, exec: execOf(root) });
  assert.equal(stale.monitor.stalled, true);
  assert.equal(stale.monitor.logAgeMin, 75);
  assert.equal(stale.workers.find((worker) => worker.id === "monitor").health, "STALLED");
  assert.ok(stale.incidents.includes("monitor: no pass for 75 min"));
});

test("STOP turns into an incident and a chip", () => {
  const root = makeFixture();
  write(root, "pipeline/STOP", "");
  const html = htmlOf(root);
  assert.ok(html.includes("every lane paused (pipeline/STOP)"));
  assert.ok(html.includes(">STOP<"));
});

test("the page carries the palette, the worker cards, the kanban and the tables", () => {
  const root = makeFixture();
  const html = htmlOf(root);
  assert.ok(html.includes("#0d1226"), "navy background");
  assert.ok(html.includes("#ff4fd8"), "magenta accent");
  assert.ok(html.includes("#ffb340"), "amber");
  assert.ok(html.includes("#ff5f6d"), "red");
  for (const label of ["Card lane", "Motion lane", "Design lane", "Art lane", "Monitor", "Freebuff"]) {
    assert.ok(html.includes(label), `worker card for ${label}`);
  }
  for (const status of ["queue", "active", "review", "blocked", "done"]) {
    assert.ok(html.includes(`<h3>${status} <span>`), `kanban column ${status}`);
  }
  assert.ok(html.includes("Waiting to merge"), "merge count per worker");
  assert.ok(html.includes('builder <span class="muted">(BUILDER.md)</span>'), "the agent that runs the lane");
  assert.ok(html.includes('animator <span class="muted">(ANIMATOR.md)</span>'), "one agent per lane");
  assert.ok(html.includes("Freebuff CLI"), "the Freebuff harness");
  assert.ok(html.includes("Scheduled tasks"));
  assert.ok(html.includes("Recent commits on main"));
  assert.ok(html.includes("Coordinator playbook"), "commit text from git log");
  // The stale warning exists but stays hidden until the inline script finds the page too old.
  assert.ok(html.includes('<p id="stale">'));
  assert.ok(html.includes("if (ageMin > 3) {"), "the page warns after 3 minutes");
  assert.ok(html.includes('id="stale"') && html.includes("display: none"), "hidden by default");
  assert.ok(html.includes("document.getElementById(\"stale\").style.display = \"block\""));
});

test("the page warns when it is older than 3 minutes", () => {
  const root = makeFixture();
  assert.equal(JSON.parse(jsonOf(root)).staleAfterMin, 3);
  const html = htmlOf(root);
  const threshold = /if \(ageMin > (\d+)\) \{/.exec(html);
  assert.notEqual(threshold, null);
  assert.equal(Number(threshold[1]), 3);
});

test("last result per lane is the newest outcome line, not the newest line of any kind", () => {
  const root = makeFixture();
  const model = modelOf(root);
  assert.equal(
    model.lanes.find((lane) => lane.id === "card").lastResult,
    "T-008 attempt 1 failed verification",
  );
  assert.equal(
    model.lanes.find((lane) => lane.id === "motion").lastResult,
    "M-003 auto-merged into main",
  );
});

test("a lane with only some status folders still renders as installed", () => {
  const empty = mkdtempSync(join(tmpdir(), "board-half-"));
  mkdirSync(join(empty, "pipeline", "tasks-art", "queue"), { recursive: true });
  write(empty, "pipeline/tasks-art/queue/A-001-art.md", "# A-001: one card\n");
  const model = buildModel(empty, { now: NOW, exec: execOf(empty) });
  const art = model.lanes.find((lane) => lane.id === "art");
  assert.notEqual(art.columns, null);
  assert.equal(art.columns.queue.length, 1);
  assert.deepEqual(art.columns.active, []);
  assert.equal(art.queueDepth, 1);
  assert.equal(art.health, "STALLED", "queued work with no log at all");
  assert.equal(model.counts.total, 1);
  assert.equal(htmlOf(empty).includes("A-001"), true);
});

test("the page marks a second-account model as such", () => {
  const root = makeFixture();
  const html = htmlOf(root);
  assert.ok(html.includes("(second account)"));
  // The runner's internal "alt|" marker is translated wherever the board names a model...
  assert.ok(html.includes("next attempt falls back to opencode-go/deepseek-v4.1-flash (second account)"));
  assert.equal(html.includes("falls back to alt|"), false);
  // ...while the raw log panels keep the log exactly as written.
  assert.ok(html.includes("==== 2026-10-07 04:45 alt|opencode/space-bunny-free"));
});

test("--json prints the same model the page renders", () => {
  const model = JSON.parse(jsonOf(makeFixture()));
  assert.ok(Array.isArray(model.workers));
  assert.ok(Array.isArray(model.lanes));
  assert.ok(typeof model.counts.total === "number");
  assert.ok(typeof model.generatedMs === "number");
  assert.ok(model.lanes.every((lane) => typeof lane.id === "string"));
  // The model the page renders and the model the JSON prints are the same shape.
  const html = htmlOf(makeFixture());
  assert.ok(html.includes(String(model.counts.blocked)));
  assert.ok(model.workers.every((worker) => typeof worker.health === "string"));
});

test("--out defaults to <root>/pipeline/board.html and --root= works as well", () => {
  const parsed = parseArgs(["--root", "C:/somewhere"]);
  assert.equal(parsed.json, false);
  assert.match(parsed.out, /pipeline[\\/]board\.html$/);
  const inline = parseArgs(["--root=C:/elsewhere", "--json", "--out=C:/tmp/b.html"]);
  assert.equal(inline.root, resolve("C:/elsewhere"));
  assert.equal(inline.json, true);
  assert.equal(inline.out, resolve("C:/tmp/b.html"));
  assert.throws(() => parseArgs(["--nope"]), /unknown argument/);
  assert.equal(main(["--help"], () => {}, () => {}), 0);
});

test("html injection in a task title is escaped everywhere it appears", () => {
  const root = makeFixture();
  write(
    root,
    "pipeline/tasks/queue/T-010-evil.md",
    "# T-010: card <script>alert(1)</script> done\n",
  );
  const html = htmlOf(root);
  assert.ok(html.includes("card &lt;script&gt;alert(1)&lt;/script&gt; done"));
  assert.equal(html.includes("<script>alert(1)"), false);
  assert.equal(html.includes("</script><script>"), false);
  // And in the JSON, where it stays data.
  assert.ok(jsonOf(root).includes("card <script>alert(1)</script> done"));
});

test("html injection from logs and modes is escaped too", () => {
  const root = makeFixture();
  write(
    root,
    "pipeline/logs/monitor.log",
    "==== 2026-10-07 04:45 model/x\n<img src=x onerror=alert(2)>\n",
  );
  write(root, "pipeline/.cooldown", "<b>until</b>");
  const html = htmlOf(root);
  assert.equal(html.includes("<img src=x"), false);
  assert.ok(html.includes("&lt;img src=x onerror=alert(2)&gt;"));
  assert.ok(html.includes("&lt;b&gt;until&lt;/b&gt;"));
});

test("esc covers every character that can break out of an attribute or tag", () => {
  assert.equal(esc(`<a href="x" title='y'>&</a>`), "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;");
  assert.equal(esc(null), "");
  assert.equal(esc(42), "42");
});