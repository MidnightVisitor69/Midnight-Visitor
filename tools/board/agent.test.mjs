// Tests for the recovery agent registry (sources.mjs), its board incidents and the agent.mjs CLI.
// Clock and filesystem are fixtures: no test touches the real registry or the image repo.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { buildModel } from "./board.mjs";
import { main as agentMain, localIso } from "./agent.mjs";
import { renderBoard } from "./render.mjs";
import { AGENT_STALE_MIN, readAgentRegistry, readGenerationJobs } from "./sources.mjs";

const NOW = Date.parse("2026-10-11T15:00:00Z");
const minsAgo = (m) => new Date(NOW - m * 60000).toISOString();

function tmp() {
  return mkdtempSync(join(tmpdir(), "agents-"));
}

const toText = (lines) =>
  lines.map((l) => (typeof l === "string" ? l : JSON.stringify(l))).join("\n") + "\n";

function registryFile(lines) {
  const path = join(tmp(), "registry.jsonl");
  writeFileSync(path, toText(lines));
  return path;
}

const noExec = () => null;

test("events fold by id in file order, later events override only the fields they carry", () => {
  const path = registryFile([
    { ts: minsAgo(50), id: "A", event: "register", task: "t1", status: "queued", model: "m1", summary: "s1" },
    { ts: minsAgo(40), id: "A", event: "update", status: "running", summary: "s2" },
    { ts: minsAgo(10), id: "B", event: "register", status: "running" },
  ]);
  const { agents, badLines, missing } = readAgentRegistry(path, NOW);
  assert.equal(badLines, 0);
  assert.equal(missing, false);
  const a = agents.find((x) => x.id === "A");
  assert.equal(a.task, "t1"); // kept from register
  assert.equal(a.model, "m1");
  assert.equal(a.status, "running"); // overridden
  assert.equal(a.summary, "s2");
  assert.equal(a.firstSeenMs, NOW - 50 * 60000);
  assert.equal(a.lastUpdateMs, NOW - 40 * 60000);
  assert.equal(agents.find((x) => x.id === "B").summary, null); // never carried: not observed
});

test("a heartbeat refreshes lastUpdate and nothing else", () => {
  const path = registryFile([
    { ts: minsAgo(60), id: "A", event: "register", status: "running", summary: "s" },
    { ts: minsAgo(5), id: "A", event: "heartbeat", status: "failed", summary: "ignored" },
  ]);
  const [a] = readAgentRegistry(path, NOW).agents;
  assert.equal(a.status, "running");
  assert.equal(a.summary, "s");
  assert.equal(a.lastUpdateAgeMin, 5);
  assert.equal(a.stale, false);
  assert.equal(a.displayStatus, "running");
});

test("stale starts after exactly 30 minutes and only applies to running", () => {
  const at = (m, status) => ({ ts: minsAgo(m), id: `S${m}${status}`, event: "register", status });
  const path = registryFile([
    at(AGENT_STALE_MIN, "running"),
    at(AGENT_STALE_MIN + 1, "running"),
    at(300, "blocked"),
    at(300, "completed"),
  ]);
  const by = Object.fromEntries(readAgentRegistry(path, NOW).agents.map((a) => [a.id, a]));
  assert.equal(by.S30running.displayStatus, "running");
  assert.equal(by.S31running.displayStatus, "stale");
  assert.equal(by.S31running.status, "running"); // last recorded state is kept
  assert.equal(by.S300blocked.displayStatus, "blocked");
  assert.equal(by.S300completed.displayStatus, "completed");
});

test("malformed lines are skipped and counted, never fatal", () => {
  const path = registryFile([
    "{not json",
    { ts: minsAgo(1), id: "A", event: "register", status: "running" },
    { ts: "yesterday", id: "A", event: "update" },
    { ts: minsAgo(1), event: "update" },
    { ts: minsAgo(1), id: "A", event: "explode" },
    "[1,2]",
  ]);
  const result = readAgentRegistry(path, NOW);
  assert.equal(result.badLines, 5);
  assert.equal(result.agents.length, 1);
});

test("a missing registry file is reported, and the page says so", () => {
  const root = tmp();
  const result = readAgentRegistry(join(root, "nope.jsonl"), NOW);
  assert.deepEqual(result, { agents: [], badLines: 0, missing: true });
  const html = renderBoard(buildModel(root, { now: NOW, exec: noExec }));
  assert.match(html, /Recovery agents/);
  assert.match(html, /no registry file/);
});

test("failed, blocked and stale agents become incidents; completed ones do not", () => {
  const root = tmp();
  mkdirSync(join(root, "pipeline", "agents"), { recursive: true });
  writeFileSync(
    join(root, "pipeline", "agents", "registry.jsonl"),
    toText([
      { ts: minsAgo(5), id: "F", event: "register", status: "failed", error: "boom" },
      { ts: minsAgo(5), id: "B", event: "register", status: "blocked", summary: "waiting on dev" },
      { ts: minsAgo(45), id: "S", event: "register", status: "running" },
      { ts: minsAgo(5), id: "C", event: "register", status: "completed" },
      "garbage",
    ]),
  );
  const model = buildModel(root, { now: NOW, exec: noExec });
  const text = model.incidents.join("\n");
  assert.match(text, /agent F.*failed - boom/);
  assert.match(text, /agent B.*blocked - waiting on dev/);
  assert.match(text, /agent S.*stale/);
  assert.doesNotMatch(text, /agent C/);
  const html = renderBoard(model);
  assert.match(html, /stale \(last: running\)/);
  assert.match(html, /1 bad lines/);
});

test("image job counts and recent records come from the state file", () => {
  const path = join(tmp(), "render_state.json");
  const done = {};
  for (let i = 0; i < 25; i += 1) {
    const rejected = i % 5 === 0;
    done[`set|card-${i}|${i}`] = { status: rejected ? "rejected" : "passed", file: `f${i}.png`, reasons: rejected ? ["bad"] : [] };
  }
  writeFileSync(path, JSON.stringify({ version: 1, candidates: 3, done }));
  const { image, video } = readGenerationJobs(path, NOW);
  assert.equal(image.total, 25);
  assert.deepEqual(image.counts, { rejected: 5, passed: 20 });
  assert.equal(image.recent.length, 20);
  assert.equal(image.recent[0].key, "set|card-24|24"); // newest first
  assert.equal(video.source, "video job source: not wired yet");
});

test("a missing image state file says no runs observed", () => {
  const missing = join(tmp(), "none.json");
  const { image } = readGenerationJobs(missing, NOW);
  assert.equal(image.missing, true);
  assert.equal(image.note, "image queue: no state file (no runs observed)");
  const model = buildModel(tmp(), { now: NOW, exec: noExec, renderStatePath: missing });
  assert.match(renderBoard(model), /no state file \(no runs observed\)/);
});

test("the CLI rejects a bad status and writes nothing", () => {
  const root = tmp();
  const errors = [];
  const code = agentMain(["update", "A", "--status", "sleeping", "--root", root], (m) => errors.push(m));
  assert.equal(code, 2);
  assert.match(errors[0], /bad status "sleeping"/);
  assert.throws(() => readFileSync(join(root, "pipeline", "agents", "registry.jsonl")));
});

test("the CLI appends one line per call with a local offset timestamp", () => {
  const root = tmp();
  const now = new Date(2026, 9, 11, 14, 20, 0);
  assert.equal(agentMain(["register", "X-1", "--status", "queued", "--owns", "a/,b/", "--root", root], () => {}, now), 0);
  assert.equal(agentMain(["heartbeat", "X-1", "--root", root], () => {}, now), 0);
  const file = join(root, "pipeline", "agents", "registry.jsonl");
  const lines = readFileSync(file, "utf8").trim().split("\n");
  assert.equal(lines.length, 2);
  const first = JSON.parse(lines[0]);
  assert.equal(first.event, "register");
  assert.deepEqual(first.owns, ["a/", "b/"]);
  assert.match(first.ts, /^2026-10-11T14:20:00[+-]\d\d:\d\d$/);
  assert.match(localIso(now), /[+-]\d\d:\d\d$/);
  assert.equal(readAgentRegistry(file, now.getTime()).agents.length, 1);
});
