#!/usr/bin/env node
// import-cards.mjs — AGENTS.md handoff step 4 (card pipeline side).
//
// Reads approved card folders, COPIES their layers into the Godot project and writes ONE SQL
// file that registers the cards. Art ships inside the app (bandwidth rule), so nothing is ever
// uploaded to Supabase Storage: the DB only stores the res://art-relative path.
//
// The importer never generates or edits art. It copies files and flips the manifest's
// `imported` flag, and it only does the latter AFTER the SQL file is on disk — a failed write
// must leave the manifests importable again.
//
// Order matters and is the whole point of this tool:
//   1. validate (T-004 helpers)   2. copy art   3. write SQL   4. set imported: true
//
// Usage: node tools/import-cards.mjs <approved_dir> [--client client] [--sql <file>]
//                                      [--banner <id> --banner-name <name>] [--alpha] [--force]

import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  findCardFolders,
  loadSchema,
  validateCardFolder,
} from "./validate-cards.mjs";

const HERE = fileURLToPath(new URL(".", import.meta.url));
const ROOT = resolve(HERE, "..");
const DEFAULT_APPROVED = join(ROOT, "shared", "art", "approved");

// Layer files we copy, in copy order. A layer is used only when it is actually present,
// so a common card simply gets null depth/char/bg paths.
const LAYERS = ["base.png", "depth.png", "char.png", "bg.png"];
const LAYER_COLUMN = {
  "base.png": "art_path",
  "depth.png": "depth_path",
  "char.png": "char_path",
  "bg.png": "bg_path",
};

// Manifest keys the image pipeline adds that the published schema does not list. `name` is the
// player-facing card title the importer prefers over character_name; `rating` is informational.
const TOLERATED_EXTRA_KEYS = new Set(["name", "rating"]);

const BANNER_COST_SINGLE = 160;
const BANNER_COST_TEN = 1600;

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    target: undefined,
    client: "client",
    sql: "supabase/seed/alpha_cards.sql",
    alpha: false,
    force: false,
    banner: undefined,
    bannerName: undefined,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--alpha") {
      args.alpha = true;
    } else if (a === "--force") {
      args.force = true;
    } else if (a === "--banner" && i + 1 < argv.length) {
      args.banner = argv[++i];
    } else if (a === "--banner-name" && i + 1 < argv.length) {
      args.bannerName = argv[++i];
    } else if (a === "--client" && i + 1 < argv.length) {
      args.client = argv[++i];
    } else if (a === "--sql" && i + 1 < argv.length) {
      args.sql = argv[++i];
    } else if (a.startsWith("--")) {
      // Silently ignoring a typo'd flag is how the previous version lost --client.
      throw new Error(`unknown flag: ${a}`);
    } else if (args.target === undefined) {
      args.target = a;
    }
  }
  return args;
}

// ---------------------------------------------------------------------------
// SQL escaping / row building
// ---------------------------------------------------------------------------

export function escapeSql(value) {
  return String(value).replace(/'/g, "''");
}

/** Renders a JS value as a SQL literal (null for null/undefined, quoted text otherwise). */
function sqlText(value) {
  if (value === null || value === undefined) return "null";
  return `'${escapeSql(value)}'`;
}

/** text[] literal; ARRAY[...] form keeps escaping in one place. */
function sqlTags(tags) {
  const items = (Array.isArray(tags) ? tags : []).map((t) => `'${escapeSql(t)}'`);
  return items.length ? `ARRAY[${items.join(", ")}]::text[]` : "ARRAY[]::text[]";
}

/**
 * One public.cards row. Layer paths are relative to res://art/ — the exact layout
 * tools/sync-approved-art.mjs stages and CardArt loads.
 */
export function buildRow(manifest, sourceDir) {
  const set = manifest.set;
  const id = manifest.card_id;
  const layerPath = (file) =>
    existsSync(join(sourceDir, file)) ? `${set}/${id}/${file}` : null;

  return {
    id,
    name: typeof manifest.name === "string" && manifest.name.trim() ? manifest.name : manifest.character_name,
    rarity: manifest.rarity,
    set,
    art_path: layerPath("base.png"),
    depth_path: layerPath("depth.png"),
    char_path: layerPath("char.png"),
    bg_path: layerPath("bg.png"),
    tags: Array.isArray(manifest.tags) ? [...manifest.tags] : [],
    source_dir: sourceDir,
  };
}

/** Drops the tolerated-extra-property complaints so a `name` field does not invalidate a drop. */
function fatalProblems(problems) {
  return problems.filter((p) => {
    const m = /^([A-Za-z0-9_]+): unexpected property$/.exec(p);
    return !(m && TOLERATED_EXTRA_KEYS.has(m[1]));
  });
}

/**
 * Walks the approved dir and returns { rows, skipped, invalid }.
 * Deterministic: rows are sorted by card_id.
 */
export function collectCards(approvedDir, { force = false, schema = loadSchema() } = {}) {
  const rows = [];
  const skipped = [];
  const invalid = [];

  for (const dir of findCardFolders(approvedDir)) {
    const folderName = basename(resolve(dir));
    let manifest;
    try {
      manifest = JSON.parse(readFileSync(join(dir, "card.json"), "utf8"));
    } catch (error) {
      invalid.push({ cardId: folderName, problems: [`card.json: unreadable (${error.message})`] });
      continue;
    }

    if (!manifest || typeof manifest !== "object") {
      invalid.push({ cardId: folderName, problems: ["card.json: not an object"] });
      continue;
    }
    if (manifest.approved !== true) {
      skipped.push({ cardId: folderName, reason: "not approved" });
      continue;
    }
    if (manifest.imported === true && !force) {
      skipped.push({ cardId: folderName, reason: "already imported" });
      continue;
    }

    const problems = fatalProblems(validateCardFolder(dir, schema).problems);
    if (problems.length > 0) {
      invalid.push({ cardId: folderName, problems });
      continue;
    }

    rows.push(buildRow(manifest, dir));
  }

  rows.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { rows, skipped, invalid };
}

/** Copies every present layer into <client>/art/<set>/<card_id>/. Returns [src, dst] pairs. */
export function copyArt(rows, clientDir) {
  const copies = [];
  for (const row of rows) {
    const dstDir = join(clientDir, "art", row.set, row.id);
    mkdirSync(dstDir, { recursive: true });
    for (const file of LAYERS) {
      const relPath = row[LAYER_COLUMN[file]];
      if (!relPath) continue;
      const src = join(row.source_dir, file);
      const dst = join(clientDir, "art", row.set, row.id, file);
      copyFileSync(src, dst);
      copies.push([src, dst]);
    }
  }
  return copies;
}

// ---------------------------------------------------------------------------
// SQL generation
// ---------------------------------------------------------------------------

const CARD_COLUMNS =
  "(id, name, rarity, set_id, art_path, depth_path, char_path, bg_path, tags, alpha)";

export function buildCardStatement(rows, alpha) {
  const values = rows.map((row) => {
    const cells = [
      sqlText(row.id),
      sqlText(row.name),
      `${sqlText(row.rarity)}::public.rarity`,
      sqlText(row.set),
      sqlText(row.art_path),
      sqlText(row.depth_path),
      sqlText(row.char_path),
      sqlText(row.bg_path),
      sqlTags(row.tags),
      alpha ? "true" : "false",
    ];
    return `  (${cells.join(", ")})`;
  });

  return [
    `insert into public.cards ${CARD_COLUMNS}`,
    "values",
    values.join(",\n"),
    "on conflict (id) do update set",
    "  name = excluded.name,",
    "  rarity = excluded.rarity,",
    "  set_id = excluded.set_id,",
    "  art_path = excluded.art_path,",
    "  depth_path = excluded.depth_path,",
    "  char_path = excluded.char_path,",
    "  bg_path = excluded.bg_path,",
    "  tags = excluded.tags,",
    "  alpha = excluded.alpha;",
  ].join("\n");
}

export function buildBannerStatement(bannerId, bannerName) {
  return [
    `insert into public.banners (id, name, cost_single, cost_ten)`,
    `values (${sqlText(bannerId)}, ${sqlText(bannerName)}, ${BANNER_COST_SINGLE}, ${BANNER_COST_TEN})`,
    "on conflict (id) do update set",
    "  name = excluded.name,",
    "  cost_single = excluded.cost_single,",
    "  cost_ten = excluded.cost_ten;",
  ].join("\n");
}

export function buildBannerCardsStatement(bannerId, rows) {
  const values = rows.map((row) => `  (${sqlText(bannerId)}, ${sqlText(row.id)})`);
  return [
    "insert into public.banner_cards (banner_id, card_id)",
    "values",
    values.join(",\n"),
    "on conflict (banner_id, card_id) do nothing;",
  ].join("\n");
}

export function buildSql(rows, { alpha = false, banner, bannerName, source } = {}) {
  const lines = [
    "-- GENERATED by tools/import-cards.mjs — do not edit by hand.",
    `-- source: ${source}`,
    `-- cards: ${rows.length}`,
    "-- Run in Supabase -> SQL Editor. Idempotent: re-running updates the same rows.",
    "",
  ];

  if (rows.length === 0) {
    lines.push("-- Nothing to import (every card was skipped or already imported).", "");
    return lines.join("\n");
  }

  lines.push("begin;", "");
  lines.push(buildCardStatement(rows, alpha));
  lines.push("");

  if (banner) {
    lines.push(buildBannerStatement(banner, bannerName || banner));
    lines.push("");
    lines.push(buildBannerCardsStatement(banner, rows));
    lines.push("");
  }

  // Placeholder cards from the seed migration: the dev retires them by hand once this set is live.
  lines.push("-- Retire the placeholder seed cards (run by hand, once the real set is live):");
  lines.push("-- update public.cards set active = false where set_id = 'test';");
  lines.push("");
  lines.push("commit;", "");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Manifest bookkeeping — only ever called after the SQL file exists on disk
// ---------------------------------------------------------------------------

export function markImported(rows) {
  const touched = [];
  for (const row of rows) {
    const path = join(row.source_dir, "card.json");
    const manifest = JSON.parse(readFileSync(path, "utf8"));
    manifest.imported = true;
    writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    touched.push(path);
  }
  return touched;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

/**
 * Imports a set of approved folders. Returns a summary, or throws (leaving every manifest
 * untouched) if the SQL file cannot be written.
 */
export function importCards({
  approvedDir = DEFAULT_APPROVED,
  clientDir = join(ROOT, "client"),
  sqlPath = join(ROOT, "supabase", "seed", "alpha_cards.sql"),
  banner,
  bannerName,
  alpha = false,
  force = false,
} = {}) {
  if (!existsSync(approvedDir)) {
    throw new Error(`folder not found: ${approvedDir}`);
  }

  const { rows, skipped, invalid } = collectCards(approvedDir, { force });
  const copies = copyArt(rows, clientDir);
  const sql = buildSql(rows, { alpha, banner, bannerName, source: approvedDir });

  mkdirSync(dirname(sqlPath), { recursive: true });
  writeFileSync(sqlPath, sql, "utf8"); // throws BEFORE any manifest is touched

  const flagged = markImported(rows);

  return { rows, copies, skipped, invalid, sqlPath, flagged };
}

export function run(argv = process.argv.slice(2), write = console.log, writeError = console.error) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    writeError(`import-cards: ${error.message}`);
    return 1;
  }

  const approvedDir = resolve(args.target ?? DEFAULT_APPROVED);
  const clientDir = resolve(ROOT, args.client);
  const sqlPath = resolve(ROOT, args.sql);

  let result;
  try {
    result = importCards({
      approvedDir,
      clientDir,
      sqlPath,
      banner: args.banner,
      bannerName: args.bannerName,
      alpha: args.alpha,
      force: args.force,
    });
  } catch (error) {
    writeError(`import-cards: ${error.message}`);
    writeError("import-cards: SQL not written, no manifests were marked imported.");
    return 1;
  }

  write("=== import-cards ===============================================");
  write(`approved : ${approvedDir}`);
  write(`client   : ${clientDir}`);
  write(`sql      : ${result.sqlPath}`);
  write(`banner   : ${args.banner ? `${args.banner} (${args.bannerName || args.banner})` : "(none)"}`);
  write(`alpha    : ${args.alpha}`);
  write("");

  for (const { cardId, reason } of result.skipped) {
    write(`SKIP  ${cardId}: ${reason}`);
  }
  for (const { cardId, problems } of result.invalid) {
    write(`BAD   ${cardId}`);
    for (const p of problems) write(`        - ${p}`);
  }

  write("");
  if (result.rows.length === 0) {
    write("0 card(s) imported.");
  } else {
    write(`${result.rows.length} card(s) imported, ${result.copies.length} layer file(s) copied:`);
    for (const row of result.rows) {
      write(`  ${row.id}  ${row.art_path}  depth=${row.depth_path ?? "null"} char=${row.char_path ?? "null"} bg=${row.bg_path ?? "null"}`);
    }
  }
  write("=================================================================");
  return result.invalid.length > 0 ? 1 : 0;
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) process.exit(run());