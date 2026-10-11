// Renders the board model (board.mjs) as one self-contained HTML page.
//
// Palette is the game's "Neon After-Hours" tokens: deep navy base, one magenta accent, amber for
// warnings, red only for incidents. The page is read on a phone in the dark, so it is one column
// of big text and wraps everywhere; no hover-only information, no horizontal scrolling.
//
// EVERY string that came from a file goes through esc(). Task files, log lines and task titles are
// written by agents, so an unescaped one would be script injection into the dev's browser.

const COLORS = {
  bg: "#0d1226",
  panel: "#151b34",
  panelEdge: "#242d52",
  text: "#d6dcfa",
  muted: "#8590bd",
  accent: "#ff4fd8",
  amber: "#ffb340",
  red: "#ff5f6d",
  ok: "#4ee39a",
};

export function esc(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Anything that is not a usable value reads as n/a, so a missing source is visible at a glance
// instead of an empty cell that looks like "zero".
function na(value, fallback = "n/a") {
  return value === null || value === undefined || value === "" ? fallback : esc(value);
}

function naNumber(value, unit = "") {
  return typeof value === "number" ? `${value}${unit}` : "n/a";
}

function age(value) {
  if (typeof value !== "number") return "n/a";
  if (value < 1) return "<1 min";
  if (value < 60) return `${Math.round(value)} min`;
  const hours = Math.floor(value / 60);
  return value % 60 === 0 ? `${hours} h` : `${hours} h ${Math.round(value % 60)} min`;
}

function clockOf(ms) {
  if (typeof ms !== "number" || !Number.isFinite(ms)) return "n/a";
  const at = new Date(ms);
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(at.getHours())}:${pad(at.getMinutes())}:${pad(at.getSeconds())}`;
}

function lineList(lines, limit = null) {
  if (lines === null) return `<p class="na">n/a</p>`;
  if (lines.length === 0) return `<p class="na">nothing yet</p>`;
  const shown = limit === null ? lines : lines.slice(0, limit);
  const items = shown.map((line) => `<li>${esc(line)}</li>`).join("");
  const more =
    limit !== null && lines.length > shown.length
      ? `<li class="muted">... ${lines.length - shown.length} more</li>`
      : "";
  return `<ul class="lines">${items}${more}</ul>`;
}

const STYLE = `
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:${COLORS.bg};color:${COLORS.text};
  font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;padding:14px 12px 40px;
  overflow-wrap:break-word}
h1{font-size:20px;margin:0 0 2px;letter-spacing:.02em}
h2{font-size:14px;margin:0 0 8px;text-transform:uppercase;letter-spacing:.09em;color:${COLORS.muted}}
h3{font-size:13px;margin:0 0 6px;color:${COLORS.muted}}
a{color:${COLORS.accent}}
.wrap{max-width:1100px;margin:0 auto}
.muted,.na{color:${COLORS.muted}}
.tiny{font-size:12px}
header{display:flex;flex-wrap:wrap;gap:6px 14px;align-items:baseline;margin-bottom:12px}
header>*{min-width:0}
header .path{overflow-wrap:anywhere}
header .when{margin-left:auto;font-variant-numeric:tabular-nums;color:${COLORS.muted}}
#stale{display:none;margin:0 0 12px;padding:8px 10px;border-radius:8px;
  background:rgba(255,95,109,.14);border:1px solid ${COLORS.red};color:#ffd8dc}
section{margin-bottom:18px}
.panel{background:${COLORS.panel};border:1px solid ${COLORS.panelEdge};border-radius:10px;padding:11px 12px;
  min-width:0}
.strip{display:flex;flex-wrap:wrap;gap:7px}
.chip{display:inline-block;padding:3px 9px;border-radius:999px;font-size:12px;max-width:100%;
  border:1px solid ${COLORS.panelEdge};background:#10162c;color:${COLORS.muted};overflow-wrap:anywhere}
.chip.on{color:${COLORS.accent};border-color:${COLORS.accent}}
.chip.warn{color:${COLORS.amber};border-color:${COLORS.amber}}
.chip.bad{color:${COLORS.red};border-color:${COLORS.red}}
.chip.good{color:${COLORS.ok};border-color:${COLORS.ok}}
.grid{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(285px,1fr))}
.worker dl{display:grid;grid-template-columns:auto 1fr;gap:2px 10px;margin:0;font-size:13px}
.worker dt{color:${COLORS.muted}}
.worker dd{margin:0;text-align:right;overflow-wrap:anywhere;min-width:0}
.worker .task{font-weight:600}
.kanban{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(215px,1fr))}
.col{min-width:0}
.col h3{display:flex;justify-content:space-between;border-bottom:1px solid ${COLORS.panelEdge};padding-bottom:5px}
.col ul{list-style:none;margin:0;padding:0}
.taskitem{border-left:3px solid ${COLORS.panelEdge};padding:5px 0 5px 8px;margin-bottom:7px}
.taskitem.active{border-left-color:${COLORS.accent}}
.taskitem.blocked{border-left-color:${COLORS.red}}
.taskitem.review{border-left-color:${COLORS.amber}}
.taskitem .ttl{font-size:13px;overflow-wrap:anywhere}
.taskitem .id{color:${COLORS.accent};font-size:12px;letter-spacing:.04em}
.taskitem .why{color:#ffc9cd;font-size:12px;overflow-wrap:anywhere}
table{width:100%;border-collapse:collapse;font-size:13px;table-layout:fixed}
th,td{text-align:left;padding:5px 6px;border-bottom:1px solid ${COLORS.panelEdge};overflow-wrap:anywhere}
th{color:${COLORS.muted};font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.06em}
td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:normal}
ul.lines{margin:0;padding-left:16px;font:12px/1.5 ui-monospace,Consolas,monospace;
  max-height:230px;overflow:auto;overflow-wrap:anywhere;color:#c3cbf1}
.cols2{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(285px,1fr))}
@media (max-width:430px){body{font-size:14px}.worker dd{text-align:left}}
`;

function modeChips(modes) {
  const chips = [];
  for (const flag of modes.flags) {
    if (!flag.on) continue;
    const cls = flag.name === "STOP" ? "bad" : flag.name === "STOP_NUDGE" ? "warn" : "on";
    chips.push(`<span class="chip ${cls}">${esc(flag.name)}</span>`);
  }
  for (const cooldown of modes.cooldowns) {
    chips.push(
      cooldown.active
        ? `<span class="chip warn">${esc(cooldown.name)} until ${na(cooldown.until)}</span>`
        : `<span class="chip">${esc(cooldown.name)} expired ${na(cooldown.until)}</span>`,
    );
  }
  for (const offset of modes.offsets) {
    chips.push(`<span class="chip">${esc(offset.name)} = ${naNumber(offset.value)}</span>`);
  }
  if (chips.length === 0) chips.push('<span class="chip">no mode flags</span>');
  return chips.join("");
}

function countChips(counts) {
  const order = ["active", "queue", "review", "blocked", "done"];
  return order
    .map((status) => {
      const cls = status === "blocked" && counts[status] > 0 ? " bad" : "";
      return `<span class="chip${cls}">${status} ${naNumber(counts[status])}</span>`;
    })
    .join("");
}

function incidentList(incidents) {
  if (incidents.length === 0) return '<span class="chip good">no incidents</span>';
  return incidents
    .map((incident) => `<span class="chip bad">${esc(incident)}</span>`)
    .join("");
}

function workerCard(worker) {
  const healthCls = { OK: "good", COOLDOWN: "warn", STALLED: "warn", BLOCKED: "bad" }[worker.health] ?? "";
  const modelCell =
    worker.model === null
      ? "n/a"
      : esc(worker.model) + (worker.altModel ? ' <span class="muted">(second account)</span>' : "");
  const task =
    worker.task === null
      ? "n/a"
      : `${esc(worker.task.id ? `${worker.task.id} ` : "")}${esc(worker.task.title)} <span class="muted">${age(worker.elapsedMin)}</span>`;
  const logCell =
    na(worker.logName) + (worker.logAgeMin === null ? "" : ` <span class="muted">(${age(worker.logAgeMin)} ago)</span>`);
  return `<div class="panel worker">
    <h3>${esc(worker.heading)} <span class="chip ${healthCls}">${esc(worker.health)}</span></h3>
    <dl>
      <dt>Agent</dt><dd>${esc(worker.agent)} <span class="muted">(${esc(worker.rules)})</span></dd>
      <dt>Harness</dt><dd>${esc(worker.harness)} ${esc(worker.version ?? "n/a")}</dd>
      <dt>Model</dt><dd>${modelCell}</dd>
      <dt class="task">Current task</dt><dd class="task">${task}</dd>
      <dt>Last result</dt><dd>${na(worker.lastResult)}</dd>
      <dt>Queue</dt><dd>${naNumber(worker.queueDepth)}</dd>
      <dt>Waiting to merge</dt><dd>${naNumber(worker.waitingToMerge)}</dd>
      <dt>Log</dt><dd>${logCell}</dd>
      ${worker.note === null ? "" : `<dt>Note</dt><dd class="muted">${esc(worker.note)}</dd>`}
    </dl>
  </div>`;
}

// A lane whose queue folder does not exist at all shows n/a in every column instead of zeroes.
const COLUMN_ORDER = ["queue", "active", "review", "blocked", "done"];
const MISSING_COLUMNS = COLUMN_ORDER.map((name) => ({ name, count: null, tasks: null }));

function taskItems(tasks) {
  if (tasks === null) return '<p class="na">n/a</p>';
  if (tasks.length === 0) return '<p class="na">empty</p>';
  return `<ul>${tasks
    .map(
      (task) => `<li class="taskitem ${task.status}">
        <div class="id">${esc(task.id)} <span class="muted">${age(task.ageMin)}</span></div>
        <div class="ttl">${esc(task.title)}</div>
        ${task.blockedReason === null ? "" : `<div class="why">Blocked: ${esc(task.blockedReason)}</div>`}
      </li>`,
    )
    .join("")}</ul>`;
}

function laneBoard(lane) {
  const columns =
    lane.columns === null
      ? MISSING_COLUMNS
      : COLUMN_ORDER.map((name) => ({
          name,
          count: lane.columns[name].length,
          tasks: lane.columns[name],
        }));
  return `<div class="panel">
    <h3>${esc(lane.label)} <span class="muted">(${esc(lane.agent)})</span></h3>
    <div class="kanban">${columns
      .map(
        (status) => `<div class="col">
          <h3>${esc(status.name)} <span>${naNumber(status.count)}</span></h3>
          ${taskItems(status.tasks)}
        </div>`,
      )
      .join("")}</div>
  </div>`;
}

function monitorPanel(monitor) {
  if (monitor === null) return '<div class="panel"><h3>Monitor</h3><p class="na">n/a</p></div>';
  return `<div class="panel">
    <h3>Monitor</h3>
    <p class="tiny muted">report ${esc(monitor.reportTime ?? "n/a")} · log ${age(monitor.logAgeMin)} ago · ${naNumber(monitor.logLines)} lines</p>
    <h3>Report (first ${monitor.reportLines.length} lines)</h3>
    ${lineList(monitor.reportLines)}
    <h3>logs/monitor.log (tail)</h3>
    ${lineList(monitor.logTail)}
  </div>`;
}

// The full sweep path is noise on a phone; the model keeps it, the page shows the file name.
function sweepName(path) {
  const parts = String(path).split(/[\\/]/);
  return parts[parts.length - 1];
}

function freebuffPanel(freebuff) {
  if (freebuff === null) return '<div class="panel"><h3>Freebuff</h3><p class="na">n/a</p></div>';
  return `<div class="panel">
    <h3>Freebuff <span class="chip ${freebuff.stalled ? "warn" : "good"}">${freebuff.stalled ? "STALLED" : "OK"}</span></h3>
    <p class="tiny muted">LOG.md ${age(freebuff.logAgeMin)} ago · sweeps ${naNumber(freebuff.sweepCount)} · nudges ${naNumber(freebuff.nudgeCount)}</p>
    <h3>freebuff/LOG.md (last 10)</h3>
    ${lineList(freebuff.logTail)}
    <h3>${na(freebuff.sweepFile === null ? null : sweepName(freebuff.sweepFile), "no sweep file")} (first table)</h3>
    ${lineList(freebuff.sweepTable)}
    <h3>logs/nudge.log (last 5)</h3>
    ${lineList(freebuff.nudgeTail)}
  </div>`;
}

// stale is its own word: a "running" agent that went quiet must never look alive.
const AGENT_CHIP = {
  queued: "", running: "on", stale: "warn", blocked: "bad",
  completed: "good", failed: "bad", cancelled: "",
};

function startedAt(ms) {
  if (typeof ms !== "number") return "n/a";
  const at = new Date(ms);
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}:${pad(at.getMinutes())}`;
}

function agentsPanel(registry) {
  if (registry.missing) return '<p class="na">no registry file</p>';
  const bad = registry.badLines > 0 ? `<p class="chip warn">${registry.badLines} bad lines</p>` : "";
  if (registry.agents.length === 0) return `${bad}<p class="na">no agents registered</p>`;
  const rows = registry.agents
    .map((a) => {
      const label = a.stale ? "stale (last: running)" : a.displayStatus;
      return `<tr>
        <td>${esc(a.id)}</td><td>${na(a.task)}</td><td>${na(a.workstream)}</td>
        <td>${na(a.provider)} / ${na(a.model)}</td>
        <td>${na(a.branch)}<br><span class="muted tiny">${na(a.worktree)}</span></td>
        <td><span class="chip ${AGENT_CHIP[a.displayStatus] ?? ""}">${esc(label)}</span></td>
        <td class="num">${startedAt(a.firstSeenMs)}</td>
        <td class="num">${startedAt(a.lastUpdateMs)} <span class="muted">(${age(a.lastUpdateAgeMin)} ago)</span></td>
        <td class="num">${age(a.elapsedMin)}</td>
        <td>${a.error ? `<span style="color:${COLORS.red}">${esc(a.error)}</span> ` : ""}${na(a.summary, a.error ? "" : "n/a")}</td>
        <td class="tiny">${na(a.results)}<br>${na(a.log, "")}</td>
      </tr>`;
    })
    .join("");
  return `${bad}<div style="overflow-x:auto"><table style="min-width:900px"><tr><th>Id</th><th>Task</th><th>Workstream</th><th>Provider / model</th><th>Branch / worktree</th><th>Status</th><th>Started</th><th>Last update</th><th>Elapsed</th><th>Summary / error</th><th>Results / log</th></tr>${rows}</table></div>`;
}

function generationBlock(jobs) {
  const image = jobs.image;
  let body;
  if (image.missing || image.unreadable) body = `<p class="na">${esc(image.note)}</p>`;
  else {
    const chips = Object.entries(image.counts)
      .map(([status, n]) => `<span class="chip ${status === "passed" ? "good" : status === "rejected" ? "warn" : ""}">${esc(status)} ${n}</span>`)
      .join("");
    const recent = image.recent
      .map((r) => `<li>${esc(r.key)} ${esc(r.status)}${r.reasons.length > 0 ? ` - ${esc(r.reasons.join("; "))}` : ""}</li>`)
      .join("");
    body = `<div class="strip">${chips || '<span class="chip">no records</span>'}</div>
      <p class="tiny muted">image queue: ${image.total} records, state file updated ${age(image.stateAgeMin)} ago; newest ${image.recent.length} below (file order, no per-record time)</p>
      <ul class="lines">${recent}</ul>`;
  }
  return `${body}<p class="tiny muted">${esc(jobs.video.source)}</p>`;
}

function scheduledTable(rows) {
  if (rows === null) return '<p class="na">n/a</p>';
  if (rows.length === 0) return '<p class="na">no Waifu* scheduled task</p>';
  return `<table><tr><th>Task</th><th>State</th><th>Last run</th><th>Result</th></tr>${rows
    .map(
      (row) => `<tr>
        <td>${esc(row.name)}</td>
        <td>${esc(row.state)}</td>
        <td class="num">${na(row.lastRunTime)}</td>
        <td class="${row.ok ? "muted" : ""}" style="${row.ok ? "" : `color:${COLORS.amber}`}">${esc(row.status)}</td>
      </tr>`,
    )
    .join("")}</table>`;
}

export function renderBoard(model) {
  const generated = clockOf(model.generatedMs);
  const lanes = model.lanes.map(laneBoard).join("");
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="60">
<title>Waifu pipeline board</title>
<style>${STYLE}</style>
</head><body><div class="wrap">
<header>
  <h1>Waifu pipeline board</h1>
  <span class="tiny muted path">${esc(model.root)}</span>
  <span class="when tiny">Updated ${generated}</span>
</header>
<p id="stale">This board is older than 3 minutes: the scheduled task that regenerates it
(<span class="muted">pipeline/board_run.ps1</span>) is not running.</p>

<section class="panel">
  <h2>Modes</h2>
  <div class="strip">${modeChips(model.modes)}</div>
  <h2 style="margin-top:12px">Tasks</h2>
  <div class="strip">${countChips(model.counts)}</div>
  <h2 style="margin-top:12px">Incidents</h2>
  <div class="strip">${incidentList(model.incidents)}</div>
</section>

<section class="panel">
  <h2>Recovery agents</h2>
  ${agentsPanel(model.agents)}
</section>

<section class="panel">
  <h2>Generation jobs</h2>
  ${generationBlock(model.generationJobs)}
</section>

<section>
  <h2>Workers</h2>
  <div class="grid">${model.workers.map(workerCard).join("")}</div>
</section>

<section>
  <h2>Lanes</h2>
  <div class="grid">${lanes}</div>
</section>

<section class="cols2">
  ${monitorPanel(model.monitor)}
  ${freebuffPanel(model.freebuff)}
</section>

<section class="panel">
  <h2>Scheduled tasks</h2>
  ${scheduledTable(model.scheduledTasks)}
</section>

<section class="panel">
  <h2>Recent commits on main</h2>
  ${model.mainCommits === null
    ? '<p class="na">n/a</p>'
    : model.mainCommits.length === 0
      ? '<p class="na">no commits</p>'
      : `<ul class="lines">${model.mainCommits
          .map((commit) => `<li>${esc(commit.sha)} ${esc(commit.text)}</li>`)
          .join("")}</ul>`}
</section>
</div>
<script>
// The page is regenerated every minute by a scheduled task; if that stops, say so instead of
// quietly showing old numbers. generatedAtMs is a number, so nothing agent-written is evaluated.
(function () {
  var generatedAtMs = ${Number(model.generatedMs)};
  var ageMin = (Date.now() - generatedAtMs) / 60000;
  if (ageMin > ${Number(model.staleAfterMin)}) {
    document.getElementById("stale").style.display = "block";
  }
})();
</script>
</body></html>
`;
  return html;
}