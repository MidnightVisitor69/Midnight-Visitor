// Tests for tools/import-cards.mjs.
//
// Every fixture is built at runtime in a temp dir (tiny PNGs with real IHDR sizes), so no
// binaries and no approved art ever enter the repo or the test's working set.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { deflateSync } from "node:zlib";

import {
  collectCards,
  escapeSql,
  importCards,
  parseArgs,
  run,
} from "./import-cards.mjs";

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

// A real (if solid-colour) PNG, so the IHDR parser runs against valid bytes.
function makePng(width, height) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 0;
  const raw = Buffer.alloc((1 + width) * height);
  return Buffer.concat([
    signature,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

const LAYERS_BY_RARITY = {
  common: ["base.png"],
  rare: ["base.png", "depth.png"],
  epic: ["base.png", "depth.png", "char.png", "bg.png"],
  legendary: ["base.png", "depth.png", "char.png", "bg.png"],
};

/** Builds a temp tree: an approved dir with one card folder per entry. */
function makeTree(cards) {
  const root = mkdtempSync(join(tmpdir(), "card-import-"));
  const approved = join(root, "approved");
  const client = join(root, "client");
  const sql = join(root, "seed", "cards.sql");
  mkdirSync(approved, { recursive: true });

  for (const card of cards) {
    const dir = join(approved, card.card_id);
    mkdirSync(dir, { recursive: true });
    const manifest = {
      card_id: card.card_id,
      character_name: card.character_name ?? "Someone",
      rarity: card.rarity ?? "common",
      set: card.set ?? "launch-01",
      tags: card.tags ?? ["tag-a"],
      approved: card.approved ?? true,
      imported: card.imported ?? false,
      gen: { model: "test-model", seed: 1, prompt_id: "test-prompt" },
    };
    if (card.name !== undefined) manifest.name = card.name;
    if (card.raw !== undefined) {
      writeFileSync(join(dir, "card.json"), card.raw, "utf8");
    } else {
      writeFileSync(join(dir, "card.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    }
    // `layers` is either the rarity's full layer list or an explicit { file: [w, h] } map.
    const layers = card.layers ?? LAYERS_BY_RARITY[manifest.rarity];
    const names = Array.isArray(layers) ? layers : Object.keys(layers);
    const sizes = Array.isArray(layers) ? {} : layers;
    for (const name of names) {
      const [w, h] = sizes[name] ?? [1024, 1536];
      writeFileSync(join(dir, name), makePng(w, h));
    }
  }

  return { root, approved, client, sql };
}

function readManifest(approved, cardId) {
  return JSON.parse(readFileSync(join(approved, cardId, "card.json"), "utf8"));
}

function readSql(path) {
  return readFileSync(path, "utf8");
}

// Splits one SQL tuple into its fields the way Postgres would read it: '' inside a literal is
// one quote, a lone quote ends the literal. Anything the importer fails to escape therefore
// shows up as a shifted/short field instead of passing silently.
function parseTuple(tuple) {
  const fields = [];
  let current = "";
  let raw = "";
  let i = tuple.indexOf("(") + 1;
  let inLiteral = false;
  let literal = false;
  let depth = 0;
  while (i < tuple.length) {
    const c = tuple[i];
    if (inLiteral) {
      if (c === "'" && tuple[i + 1] === "'") {
        current += "'";
        i += 2;
        continue;
      }
      if (c === "'") {
        inLiteral = false;
        i += 1;
        continue;
      }
      current += c;
      i += 1;
      continue;
    }
    if (c === "'") {
      inLiteral = true;
      literal = true;
      i += 1;
      continue;
    }
    if (c === "[") depth += 1;
    if (c === "]") depth -= 1;
    if (c === "," && depth === 0) {
      fields.push(literal ? current : raw.trim());
      current = "";
      raw = "";
      literal = false;
      i += 1;
      continue;
    }
    if (c === ")" && depth === 0) break;
    raw += c;
    i += 1;
  }
  fields.push(literal ? current : raw.trim());
  return fields;
}

function cardValues(sql) {
  const after = sql.split("insert into public.cards")[1];
  if (after === undefined || !after.includes("\nvalues\n")) return [];
  const block = after.split("\nvalues\n")[1].split("on conflict")[0];
  return block
    .split("\n")
    .filter((line) => line.trimStart().startsWith("("))
    .map((line) => parseTuple(line));
}

const baseImport = (t, extra = {}) => ({
  approvedDir: t.approved,
  clientDir: t.client,
  sqlPath: t.sql,
  ...extra,
});

// --- tests -----------------------------------------------------------------

test("3 valid approved cards -> 3 folders copied, SQL has 3 rows + banner rows, flags set", () => {
  const t = makeTree([
    { card_id: "alpha-common", rarity: "common", character_name: "Common One" },
    { card_id: "alpha-rare", rarity: "rare", character_name: "Rare One", tags: ["rare-tag"] },
    { card_id: "alpha-epic", rarity: "epic", character_name: "Epic One", tags: ["a", "b"] },
  ]);

  const result = importCards(
    baseImport(t, { banner: "kat-alpha", bannerName: "KaT Alpha", alpha: true }),
  );

  assert.equal(result.rows.length, 3);
  assert.equal(result.invalid.length, 0);
  assert.equal(result.skipped.length, 0);

  for (const id of ["alpha-common", "alpha-rare", "alpha-epic"]) {
    assert.ok(
      existsSync(join(t.client, "art", "launch-01", id, "base.png")),
      `${id}/base.png must be copied into client/art`,
    );
    assert.equal(readManifest(t.approved, id).imported, true, `${id} must be flagged imported`);
  }
  assert.ok(existsSync(join(t.client, "art", "launch-01", "alpha-epic", "char.png")));
  assert.ok(existsSync(join(t.client, "art", "launch-01", "alpha-epic", "bg.png")));
  assert.ok(existsSync(join(t.client, "art", "launch-01", "alpha-rare", "depth.png")));

  const sql = readSql(t.sql);
  const values = sql.split("insert into public.cards")[1].split("on conflict")[0];
  assert.equal(values.match(/^\s{2}\('/gm).length, 3, "expected exactly 3 card rows");
  assert.equal(sql.match(/insert into public\.banners/g).length, 1);
  assert.match(sql, /values \('kat-alpha', 'KaT Alpha', 160, 1600\)/);
  assert.equal(sql.match(/insert into public\.banner_cards/g).length, 1);
  assert.match(sql, /\('kat-alpha', 'alpha-common'\)/);
  assert.match(sql, /\('kat-alpha', 'alpha-epic'\)/);
  assert.match(sql, /on conflict \(banner_id, card_id\) do nothing;/);
  assert.match(sql, /-- update public\.cards set active = false where set_id = 'test';/);
  assert.deepEqual(
    cardValues(sql).map((f) => f[9]),
    ["true", "true", "true"],
    "--alpha must set the alpha column on every row",
  );
});

test("unapproved card skipped; invalid card skipped and reported; re-run imports nothing", () => {
  const t = makeTree([
    { card_id: "good-one", rarity: "common" },
    { card_id: "not-approved", rarity: "common", approved: false },
    // epic without char.png -> invalid
    {
      card_id: "broken-epic",
      rarity: "epic",
      layers: { "base.png": [1024, 1536], "depth.png": [1024, 1536], "bg.png": [1024, 1536] },
    },
  ]);

  const result = importCards(baseImport(t));

  assert.deepEqual(result.rows.map((r) => r.id), ["good-one"]);
  assert.deepEqual(
    result.skipped.map((s) => [s.cardId, s.reason]),
    [["not-approved", "not approved"]],
  );
  assert.equal(result.invalid.length, 1);
  assert.equal(result.invalid[0].cardId, "broken-epic");
  assert.ok(
    result.invalid[0].problems.some((p) => p.includes("char.png")),
    `expected a char.png problem, got ${result.invalid[0].problems.join(" | ")}`,
  );
  assert.ok(
    !existsSync(join(t.client, "art", "launch-01", "broken-epic")),
    "an invalid card must not be copied into the client",
  );
  assert.equal(readManifest(t.approved, "not-approved").imported, false);
  assert.equal(readManifest(t.approved, "broken-epic").imported, false);
  assert.equal(readManifest(t.approved, "good-one").imported, true);

  const report = [];
  assert.equal(run([t.approved, "--client", t.client, "--sql", t.sql], (l) => report.push(l)), 1);
  assert.ok(
    report.some((l) => l.includes("SKIP  not-approved: not approved")),
    `expected the skip to be reported, got: ${report.join(" | ")}`,
  );
  assert.ok(
    report.some((l) => l.includes("BAD   broken-epic")),
    `expected the bad card to be reported, got: ${report.join(" | ")}`,
  );

  // Second run: everything is already imported, so nothing is imported again.
  const second = importCards(baseImport(t));
  assert.equal(second.rows.length, 0);
  assert.equal(second.copies.length, 0);
  assert.equal(second.flagged.length, 0);
  assert.ok(
    second.skipped.some((s) => s.cardId === "good-one" && s.reason === "already imported"),
    "good-one must be skipped as already imported",
  );
  const sql = readSql(t.sql);
  assert.match(sql, /Nothing to import/);
  assert.equal(sql.match(/^\s{2}\('/gm), null, "no card rows may be re-emitted");

  // --force re-imports.
  const forced = importCards(baseImport(t, { force: true }));
  assert.deepEqual(forced.rows.map((r) => r.id), ["good-one"]);
});

test("a name with an apostrophe is escaped correctly", () => {
  const t = makeTree([
    { card_id: "rock-n-roll", rarity: "common", name: "KaT \u00b7 Rock 'n' Roll" },
    { card_id: "no-name-field", rarity: "common", character_name: "Plain Character" },
    { card_id: "quotes-everywhere", rarity: "common", name: "'' O''Brien ''" },
  ]);

  const result = importCards(baseImport(t));
  const rows = cardValues(readSql(t.sql));

  assert.equal(escapeSql("a'b"), "a''b");
  assert.equal(rows.length, 3);
  assert.deepEqual(
    rows.map((f) => f[1]),
    ["Plain Character", "'' O''Brien ''", "KaT \u00b7 Rock 'n' Roll"],
    "every name must round-trip through the SQL literal",
  );
  assert.deepEqual(rows.map((f) => f[0]), ["no-name-field", "quotes-everywhere", "rock-n-roll"]);

  const raw = readSql(t.sql);
  assert.match(raw, /\('rock-n-roll', 'KaT \u00b7 Rock ''n'' Roll',/);
  assert.match(raw, /\('no-name-field', 'Plain Character',/);
});

test("manifest name wins over character_name", () => {
  const t = makeTree([
    { card_id: "titled", rarity: "common", name: "The Title", character_name: "Character" },
    { card_id: "untitled", rarity: "common", character_name: "Character" },
    { card_id: "blank-name", rarity: "common", name: "   ", character_name: "Character" },
  ]);
  const names = importCards(baseImport(t)).rows.map((r) => r.name);
  assert.deepEqual(names, ["Character", "The Title", "Character"]);
});

test("layer paths are <set>/<card_id>/<file>, null when the layer file is absent", () => {
  const t = makeTree([
    { card_id: "plain-common", rarity: "common" },
    { card_id: "full-epic", rarity: "epic", set: "set-two" },
  ]);
  const rows = importCards(baseImport(t)).rows;
  const common = rows.find((r) => r.id === "plain-common");
  const epic = rows.find((r) => r.id === "full-epic");

  assert.equal(common.art_path, "launch-01/plain-common/base.png");
  assert.equal(common.depth_path, null);
  assert.equal(common.char_path, null);
  assert.equal(common.bg_path, null);

  assert.equal(epic.art_path, "set-two/full-epic/base.png");
  assert.equal(epic.depth_path, "set-two/full-epic/depth.png");
  assert.equal(epic.char_path, "set-two/full-epic/char.png");
  assert.equal(epic.bg_path, "set-two/full-epic/bg.png");

  const sql = readSql(t.sql);
  assert.match(sql, /\('plain-common', 'Someone', 'common'::public\.rarity, 'launch-01', 'launch-01\/plain-common\/base\.png', null, null, null,/);
  assert.match(sql, /\('full-epic', 'Someone', 'epic'::public\.rarity, 'set-two', 'set-two\/full-epic\/base\.png', 'set-two\/full-epic\/depth\.png', 'set-two\/full-epic\/char\.png', 'set-two\/full-epic\/bg\.png',/);
  assert.ok(!sql.includes("shared/art/approved"), "paths must never point at the handoff folder");
});

test("a failed SQL write leaves every manifest un-imported", () => {
  const t = makeTree([
    { card_id: "keeper-one", rarity: "common" },
    { card_id: "keeper-two", rarity: "rare" },
  ]);
  // Pointing --sql at a directory makes writeFileSync throw (EISDIR) at exactly the right
  // moment: after the copy, before the manifests may be flagged.
  const unwritableSql = join(t.root, "not-a-file");
  mkdirSync(unwritableSql, { recursive: true });

  assert.throws(
    () => importCards(baseImport(t, { sqlPath: unwritableSql })),
    /EISDIR|EPERM|EACCES|directory/i,
  );
  assert.equal(readManifest(t.approved, "keeper-one").imported, false);
  assert.equal(readManifest(t.approved, "keeper-two").imported, false);

  const report = [];
  const code = run([t.approved, "--client", t.client, "--sql", unwritableSql], (l) => report.push(l), () => {});
  assert.equal(code, 1);
  assert.equal(readManifest(t.approved, "keeper-one").imported, false);

  // And the retry succeeds.
  const retry = importCards(baseImport(t));
  assert.equal(retry.rows.length, 2);
  assert.equal(readManifest(t.approved, "keeper-one").imported, true);
});

test("rows are emitted in deterministic (card_id) order", () => {
  const t = makeTree([
    { card_id: "zeta-card", rarity: "common" },
    { card_id: "alpha-card", rarity: "common" },
    { card_id: "mid-card", rarity: "common" },
  ]);
  importCards(baseImport(t));
  const firstText = readSql(t.sql);
  const rowsOrder = firstText.split("insert into public.cards")[1].split("on conflict")[0];
  assert.deepEqual(rowsOrder.match(/'([a-z]+-card)'/g), ["'alpha-card'", "'mid-card'", "'zeta-card'"]);

  importCards(baseImport(t, { force: true }));
  assert.equal(readSql(t.sql), firstText, "SQL output must be byte-identical across runs");
});

test("parseArgs reads every documented flag and rejects unknown ones", () => {
  const args = parseArgs([
    "some/dir",
    "--client", "client2",
    "--sql", "out/cards.sql",
    "--banner", "kat-alpha",
    "--banner-name", "KaT Alpha",
    "--alpha",
    "--force",
  ]);
  assert.deepEqual(args, {
    target: "some/dir",
    client: "client2",
    sql: "out/cards.sql",
    banner: "kat-alpha",
    bannerName: "KaT Alpha",
    alpha: true,
    force: true,
  });

  assert.deepEqual(parseArgs([]).client, "client");
  assert.deepEqual(parseArgs([]).sql, "supabase/seed/alpha_cards.sql");
  assert.throws(() => parseArgs(["--clinet", "client2"]), /unknown flag: --clinet/);
});

test("run returns 1 when a card is invalid, 0 when everything imports", () => {
  const clean = makeTree([{ card_id: "clean-card", rarity: "common" }]);
  assert.equal(run([clean.approved, "--client", clean.client, "--sql", clean.sql], () => {}, () => {}), 0);

  const dirty = makeTree([{ card_id: "bad-card", rarity: "epic", layers: {} }]);
  assert.equal(run([dirty.approved, "--client", dirty.client, "--sql", dirty.sql], () => {}, () => {}), 1);
});

test("collectCards ignores manifests it cannot read", () => {
  const t = makeTree([{ card_id: "good-two", rarity: "common" }]);
  writeFileSync(join(t.approved, "good-two", "card.json"), "{ not json", "utf8");
  const result = collectCards(t.approved);
  assert.equal(result.rows.length, 0);
  assert.equal(result.invalid.length, 1);
  assert.match(result.invalid[0].problems[0], /unreadable/);
});

test("base.png of exactly 1024x1536 is accepted", () => {
  const t = makeTree([{ card_id: "exact-size", rarity: "common" }]);
  const result = importCards(baseImport(t));
  assert.deepEqual(result.rows.map((r) => r.id), ["exact-size"]);
  assert.equal(result.invalid.length, 0);
});