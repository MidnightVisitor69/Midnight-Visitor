// Validates card handoff folders against shared/card_manifest.schema.json.
//
// READ-ONLY by design: the importer may only read the drop the image pipeline owns, never
// write, move or delete inside it. Bad drops must fail loudly here instead of reaching the DB.
//
// Standard library only; the schema-subset evaluator below exists so tools/ has no npm deps.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = fileURLToPath(new URL(".", import.meta.url));
export const SCHEMA_PATH = resolve(HERE, "..", "shared", "card_manifest.schema.json");

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

// Layer requirements grow with rarity (AGENTS.md "Card visuals").
export const REQUIRED_LAYERS = {
  common: ["base.png"],
  rare: ["base.png", "depth.png"],
  epic: ["base.png", "depth.png", "char.png", "bg.png"],
  legendary: ["base.png", "depth.png", "char.png", "bg.png"],
};

export const MIN_WIDTH = 1024;
export const MIN_HEIGHT = 1536;

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Reads width/height straight out of the PNG IHDR header (first chunk after the 8-byte magic).
export function readPngSize(buffer) {
  if (buffer.length < 24) throw new Error("not a PNG (file too short)");
  for (let i = 0; i < PNG_SIGNATURE.length; i++) {
    if (buffer[i] !== PNG_SIGNATURE[i]) throw new Error("not a PNG (bad signature)");
  }
  const chunkType = buffer.toString("ascii", 12, 16);
  if (chunkType !== "IHDR") throw new Error("not a PNG (missing IHDR)");
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

let cachedSchema = null;
export function loadSchema(schemaPath = SCHEMA_PATH) {
  if (schemaPath === SCHEMA_PATH && cachedSchema) return cachedSchema;
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  if (schemaPath === SCHEMA_PATH) cachedSchema = schema;
  return schema;
}

function jsonType(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (Number.isInteger(value)) return "integer";
  if (typeof value === "number") return "number";
  return typeof value;
}

// Minimal JSON Schema (draft 2020-12 subset used by our manifest). Returns problem strings.
export function validateAgainstSchema(value, schema, path = "") {
  const problems = [];
  if (!isPlainObject(schema)) return problems;
  const label = path || "card.json";

  if (schema.type !== undefined) {
    const actual = jsonType(value);
    const typeOk = actual === schema.type || (schema.type === "number" && actual === "integer");
    if (!typeOk) {
      problems.push(`${label}: must be of type ${schema.type}`);
      return problems;
    }
  }

  if (Array.isArray(schema.enum) && !schema.enum.some((candidate) => candidate === value)) {
    problems.push(`${label}: must be one of: ${schema.enum.join(", ")}`);
  }

  if (typeof value === "string") {
    if (schema.pattern !== undefined && !new RegExp(schema.pattern).test(value)) {
      problems.push(`${label}: must match pattern ${schema.pattern}`);
    }
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      problems.push(`${label}: must be at least ${schema.minLength} characters long`);
    }
    if (schema.maxLength !== undefined && value.length > schema.maxLength) {
      problems.push(`${label}: must be at most ${schema.maxLength} characters long`);
    }
  }

  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      problems.push(`${label}: must be >= ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      problems.push(`${label}: must be <= ${schema.maximum}`);
    }
  }

  if (Array.isArray(value)) {
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      problems.push(`${label}: must contain at most ${schema.maxItems} items`);
    }
    if (schema.uniqueItems === true) {
      const seen = new Set();
      for (const item of value) {
        const key = JSON.stringify(item);
        if (seen.has(key)) {
          problems.push(`${label}: must not contain duplicate items`);
          break;
        }
        seen.add(key);
      }
    }
    if (schema.items !== undefined) {
      value.forEach((item, index) => {
        problems.push(...validateAgainstSchema(item, schema.items, `${label}[${index}]`));
      });
    }
  }

  if (isPlainObject(value)) {
    for (const requiredKey of schema.required ?? []) {
      if (!Object.prototype.hasOwnProperty.call(value, requiredKey)) {
        const childPath = path ? `${path}.${requiredKey}` : requiredKey;
        problems.push(`${childPath}: required property is missing`);
      }
    }
    const properties = schema.properties ?? {};
    for (const key of Object.keys(value)) {
      const childPath = path ? `${path}.${key}` : key;
      if (Object.prototype.hasOwnProperty.call(properties, key)) {
        problems.push(...validateAgainstSchema(value[key], properties[key], childPath));
      } else if (schema.additionalProperties === false) {
        problems.push(`${childPath}: unexpected property`);
      }
    }
  }

  return problems;
}

export function validateManifest(manifest, schema = loadSchema()) {
  return validateAgainstSchema(manifest, schema);
}

function checkLayers(dir, rarity) {
  const problems = [];
  let baseSize = null;
  for (const file of REQUIRED_LAYERS[rarity]) {
    const filePath = join(dir, file);
    if (!existsSync(filePath) || !statSync(filePath).isFile()) {
      problems.push(`missing required file for rarity ${rarity}: ${file}`);
      continue;
    }
    let size;
    try {
      size = readPngSize(readFileSync(filePath));
    } catch (error) {
      problems.push(`${file}: ${error.message}`);
      continue;
    }
    if (file === "base.png") {
      baseSize = size;
      if (size.width < MIN_WIDTH || size.height < MIN_HEIGHT) {
        problems.push(
          `base.png: ${size.width}x${size.height} is smaller than the minimum ${MIN_WIDTH}x${MIN_HEIGHT}`,
        );
      }
      if (size.width * 3 !== size.height * 2) {
        problems.push(`base.png: ${size.width}x${size.height} is not a 2:3 portrait`);
      }
    } else if (baseSize && (size.width !== baseSize.width || size.height !== baseSize.height)) {
      problems.push(
        `${file}: size ${size.width}x${size.height} does not match base.png size ${baseSize.width}x${baseSize.height}`,
      );
    }
  }
  return problems;
}

export function validateCardFolder(dir, schema = loadSchema()) {
  const folderName = basename(resolve(dir));
  const manifestPath = join(dir, "card.json");

  let text;
  try {
    text = readFileSync(manifestPath, "utf8");
  } catch {
    return { cardId: folderName, problems: ["card.json: is missing or unreadable"] };
  }

  let manifest;
  try {
    manifest = JSON.parse(text);
  } catch (error) {
    return { cardId: folderName, problems: [`card.json: invalid JSON (${error.message})`] };
  }

  const cardId =
    isPlainObject(manifest) && typeof manifest.card_id === "string" ? manifest.card_id : folderName;
  const problems = validateManifest(manifest, schema);

  if (isPlainObject(manifest)) {
    if (typeof manifest.card_id === "string" && manifest.card_id !== folderName) {
      problems.push(`folder name "${folderName}" does not match card_id "${manifest.card_id}"`);
    }
    if (manifest.imported === true && manifest.approved !== true) {
      problems.push("imported is true but approved is false");
    }
    if (typeof manifest.rarity === "string" && REQUIRED_LAYERS[manifest.rarity]) {
      problems.push(...checkLayers(dir, manifest.rarity));
    }
  }

  return { cardId, problems };
}

export function findCardFolders(rootDir) {
  const root = resolve(rootDir);
  if (existsSync(join(root, "card.json"))) return [root];

  const found = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const child = join(dir, entry.name);
      if (existsSync(join(child, "card.json"))) found.push(child);
      else walk(child);
    }
  };
  walk(root);
  return found.sort();
}

export function validateCards(rootDir, schema = loadSchema()) {
  return findCardFolders(rootDir).map((dir) => validateCardFolder(dir, schema));
}

export function run(argv = process.argv.slice(2), write = console.log, writeError = console.error) {
  const target = argv[0];
  if (!target) {
    writeError("usage: node tools/validate-cards.mjs <card-folder|parent-folder>");
    return 1;
  }
  if (!existsSync(target)) {
    writeError(`validate-cards: folder not found: ${target}`);
    return 1;
  }
  const folders = findCardFolders(target);
  if (folders.length === 0) {
    writeError(`validate-cards: no card.json found under ${target}`);
    return 1;
  }
  let problemCount = 0;
  for (const dir of folders) {
    const { cardId, problems } = validateCardFolder(dir);
    for (const problem of problems) {
      write(`${cardId}: ${problem}`);
      problemCount += 1;
    }
  }
  return problemCount === 0 ? 0 : 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) process.exit(run());
