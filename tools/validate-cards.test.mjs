// Tests for tools/validate-cards.mjs. The fixtures only carry card.json; PNGs are generated
// here at runtime so no binaries are ever committed.

import { test } from "node:test";
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";

import {
  findCardFolders,
  readPngSize,
  run,
  validateCardFolder,
  validateCards,
} from "./validate-cards.mjs";

const FIXTURES = fileURLToPath(new URL("./fixtures/", import.meta.url));

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

// A real (if solid-colour) PNG so the IHDR parser is exercised against valid bytes.
function makePng(width, height) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 0; // grayscale
  const raw = Buffer.alloc((1 + width) * height); // one filter byte per scanline
  return Buffer.concat([
    signature,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function stage(fixture, folderName) {
  const manifest = JSON.parse(readFileSync(join(FIXTURES, fixture, "card.json"), "utf8"));
  const root = mkdtempSync(join(tmpdir(), "card-validate-"));
  const dir = join(root, folderName ?? manifest.card_id);
  mkdirSync(dir, { recursive: true });
  copyFileSync(join(FIXTURES, fixture, "card.json"), join(dir, "card.json"));
  return { root, dir, manifest };
}

function writePng(dir, name, width, height) {
  writeFileSync(join(dir, name), makePng(width, height));
}

function problemsOf(dir) {
  return validateCardFolder(dir).problems;
}

test("valid common card passes", () => {
  const { dir } = stage("valid-common");
  writePng(dir, "base.png", 1024, 1536);
  assert.deepEqual(problemsOf(dir), []);
});

test("valid rare card passes", () => {
  const { dir } = stage("valid-rare");
  writePng(dir, "base.png", 1024, 1536);
  writePng(dir, "depth.png", 1024, 1536);
  assert.deepEqual(problemsOf(dir), []);
});

test("valid epic card passes", () => {
  const { dir } = stage("valid-epic");
  for (const file of ["base.png", "depth.png", "char.png", "bg.png"]) {
    writePng(dir, file, 1024, 1536);
  }
  assert.deepEqual(problemsOf(dir), []);
});

test("valid legendary card passes", () => {
  const { dir } = stage("valid-legendary");
  for (const file of ["base.png", "depth.png", "char.png", "bg.png"]) {
    writePng(dir, file, 1024, 1536);
  }
  assert.deepEqual(problemsOf(dir), []);
});

test("bad card_id fails on the schema pattern", () => {
  const { dir } = stage("bad-id");
  writePng(dir, "base.png", 1024, 1536);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /card_id: must match pattern/);
});

test("unknown rarity fails on the enum", () => {
  const { dir } = stage("unknown-rarity");
  writePng(dir, "base.png", 1024, 1536);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /rarity: must be one of: common, rare, epic, legendary/);
});

test("extra property fails", () => {
  const { dir } = stage("extra-prop");
  writePng(dir, "base.png", 1024, 1536);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /sneaky: unexpected property/);
});

test("epic missing char.png fails", () => {
  const { dir } = stage("epic-missing-char");
  writePng(dir, "base.png", 1024, 1536);
  writePng(dir, "depth.png", 1024, 1536);
  writePng(dir, "bg.png", 1024, 1536);
  const problems = problemsOf(dir);
  assert.ok(
    problems.some((p) => p === "missing required file for rarity epic: char.png"),
    `expected a missing char.png problem, got: ${problems.join(" | ")}`,
  );
  assert.ok(!problems.some((p) => p.includes("bg.png")), "bg.png should be present");
});

test("rare missing depth.png fails", () => {
  const { dir } = stage("rare-missing-depth");
  writePng(dir, "base.png", 1024, 1536);
  const problems = problemsOf(dir);
  assert.ok(
    problems.some((p) => p === "missing required file for rarity rare: depth.png"),
    `expected a missing depth.png problem, got: ${problems.join(" | ")}`,
  );
});

test("base 1000x1500 is too small", () => {
  const { dir } = stage("base-too-small");
  writePng(dir, "base.png", 1000, 1500);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /base\.png: 1000x1500 is smaller than the minimum 1024x1536/);
});

test("base 1024x1024 is not 2:3", () => {
  const { dir } = stage("base-not-2-3");
  writePng(dir, "base.png", 1024, 1024);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /base\.png: 1024x1024 is not a 2:3 portrait/);
});

test("depth size mismatch fails", () => {
  const { dir } = stage("depth-mismatch");
  writePng(dir, "base.png", 1024, 1536);
  writePng(dir, "depth.png", 512, 768);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /depth\.png: size 512x768 does not match base\.png size 1024x1536/);
});

test("folder name must equal card_id", () => {
  const { dir } = stage("folder-mismatch", "wrong-folder-name");
  writePng(dir, "base.png", 1024, 1536);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /folder name "wrong-folder-name" does not match card_id "right-name"/);
});

test("imported true without approved fails", () => {
  const { dir } = stage("imported-without-approved");
  writePng(dir, "base.png", 1024, 1536);
  const joined = problemsOf(dir).join("\n");
  assert.match(joined, /imported is true but approved is false/);
});

test("readPngSize rejects bytes that are not a PNG", () => {
  assert.throws(() => readPngSize(Buffer.from("nope")), /not a PNG/);
});

test("findCardFolders walks a parent and returns each card folder", () => {
  const { root } = stage("valid-common");
  const nested = join(root, "nested", "valid-rare");
  mkdirSync(nested, { recursive: true });
  copyFileSync(join(FIXTURES, "valid-rare", "card.json"), join(nested, "card.json"));
  const folders = findCardFolders(root);
  assert.equal(folders.length, 2);
});

test("validateCards reports every card under a parent", () => {
  const { root } = stage("valid-common");
  writePng(join(root, "fixture-common"), "base.png", 1024, 1536);
  const results = validateCards(root);
  assert.equal(results.length, 1);
  assert.deepEqual(results[0].problems, []);
});

test("run returns 0 for a valid folder and 1 with '<card_id>: <problem>' lines otherwise", () => {
  const valid = stage("valid-common");
  writePng(valid.dir, "base.png", 1024, 1536);
  assert.equal(run([valid.dir], () => {}), 0);

  const broken = stage("epic-missing-char");
  writePng(broken.dir, "base.png", 1024, 1536);
  writePng(broken.dir, "depth.png", 1024, 1536);
  writePng(broken.dir, "bg.png", 1024, 1536);
  const lines = [];
  assert.equal(run([broken.dir], (line) => lines.push(line)), 1);
  assert.ok(
    lines.some(
      (line) => line.startsWith("epic-missing-char: ") && line.includes("char.png"),
    ),
    `expected a prefixed char.png problem, got: ${lines.join(" | ")}`,
  );
});
