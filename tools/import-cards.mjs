// Validates and prepares card folders from shared/art/approved for import.
// READ-ONLY by design: never writes, moves, or deletes inside approved folders.
// Emits reviewable SQL preparation artifacts; does not connect to Supabase or
// execute any remote operations.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  loadSchema,
  validateAgainstSchema,
  validateManifest,
  findCardFolders,
  validateCards,
} from "./validate-cards.mjs";

const HERE = fileURLToPath(new URL(".", import.meta.url));
const SCHEMA_PATH = resolve(HERE, "..", "shared", "card_manifest.schema.json");

// Layer requirements grow with rarity (AGENTS.md "Card visuals").
// Duplicated here so we do not depend on validate-cards.mjs exports.
const REQUIRED_LAYERS = {
  common: ["base.png"],
  rare: ["base.png", "depth.png"],
  epic: ["base.png", "depth.png", "char.png", "bg.png"],
  legendary: ["base.png", "depth.png", "char.png", "bg.png"],
};

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** @param {*} value */
function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv = process.argv.slice(2)) {
  const args = {
    target: undefined,
    alpha: false,
    banner: undefined,
    bannerName: undefined,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--alpha") {
      args.alpha = true;
    } else if (a === "--banner" && i + 1 < argv.length) {
      args.banner = argv[++i];
    } else if (a === "--banner-name" && i + 1 < argv.length) {
      args.bannerName = argv[++i];
    } else if (!args.target) {
      args.target = a;
    }
  }
  return args;
}

// ---------------------------------------------------------------------------
// PNG signature and IHDR reader (from validate-cards.mjs)
// ---------------------------------------------------------------------------

const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

function readPngSize(buffer) {
  if (buffer.length < 24) throw new Error("not a PNG (file too short)");
  for (let i = 0; i < PNG_SIG.length; i++) {
    if (buffer[i] !== PNG_SIG[i]) throw new Error("not a PNG (bad signature)");
  }
  const chunkType = buffer.toString("ascii", 12, 16);
  if (chunkType !== "IHDR") throw new Error("not a PNG (missing IHDR)");
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

// ---------------------------------------------------------------------------
// Layer checking — replicates the logic from validate-cards.mjs
// ---------------------------------------------------------------------------

function checkLayers(dir, rarity) {
  const problems = [];
  let baseSize = null;
  const required = REQUIRED_LAYERS[rarity];
  if (!required) return problems;
  for (const file of required) {
    const filePath = join(dir, file);
    if (!existsSync(filePath) || !statSync(filePath).isFile()) {
      problems.push(
        "missing required file for rarity " + rarity + ": " + file,
      );
      continue;
    }
    let size;
    try {
      const buf = readFileSync(filePath);
      // Validate PNG signature
      if (buf.length < 24) {
        problems.push(file + ": file too short to be a PNG");
        continue;
      }
      for (let i = 0; i < PNG_SIG.length; i++) {
        if (buf[i] !== PNG_SIG[i]) {
          problems.push(file + ": bad PNG signature");
          continue;
        }
      }
      const chunkType = buf.toString("ascii", 12, 16);
      if (chunkType !== "IHDR") {
        problems.push(file + ": missing IHDR");
        continue;
      }
      size = { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
    } catch (error) {
      problems.push(file + ": " + error.message);
      continue;
    }
    if (file === "base.png") {
      baseSize = size;
      if (size.width < 1024 || size.height < 1536) {
        problems.push(
          "base.png: " +
            size.width +
            "x" +
            size.height +
            " is smaller than the minimum 1024x1536",
        );
      }
      if (size.width * 3 !== size.height * 2) {
        problems.push(
          "base.png: " + size.width + "x" + size.height + " is not a 2:3 portrait",
        );
      }
    } else if (baseSize && (size.width !== baseSize.width || size.height !== baseSize.height)) {
      problems.push(
        file + ": size " + size.width + "x" + size.height + " does not match base.png size " + baseSize.width + "x" + baseSize.height,
      );
    }
  }
  return problems;
}

// ---------------------------------------------------------------------------
// SQL preparation helpers — build statements using string concatenation
// ---------------------------------------------------------------------------

function buildCardSql(card, alpha) {
  const rarity = card.rarity || "common";
  const cardId = card.card_id || basename(resolve(card._dir ?? ""));
  const characterName = card.character_name || "Unknown";
  const setId = card.set || "unknown";
  const tags = card.tags || [];
  const approved = card.approved !== undefined ? card.approved : true;

  // Build art paths relative to the repo root
  const artPath = "shared/art/approved/" + cardId + "/base.png";
  const depthPath =
    rarity !== "common"
      ? "shared/art/approved/" + cardId + "/depth.png"
      : null;
  const charPath =
    rarity !== "common" && rarity !== "rare"
      ? "shared/art/approved/" + cardId + "/char.png"
      : null;
  const bgPath =
    rarity !== "common" && rarity !== "rare"
      ? "shared/art/approved/" + cardId + "/bg.png"
      : null;

  // tags SQL value
  let tagsValue = "'{";
  for (let i = 0; i < tags.length; i += 1) {
    if (i > 0) tagsValue += ",";
    tagsValue += tags[i];
  }
  tagsValue += "}'::text[]";

  const alphaSql = alpha ? "true" : "false";

  // ---- assemble INSERT statement via concatenation ----
  let sql = "INSERT INTO public.cards ";
  sql += "(id, name, rarity, set_id, art_path, depth_path, char_path, bg_path, tags, active, alpha) ";
  sql += "VALUES ";

  // Escape single quotes for SQL
  function escapeSql(s) {
    return String(s).replace(/'/g, "''");
  }
  const idEscaped = escapeSql(cardId);
  const nameEscaped = escapeSql(characterName);
  const setIdEscaped = escapeSql(setId);
  const artPathEscaped = escapeSql(artPath);

  const depthSql = depthPath ? "'" + escapeSql(depthPath) + "'::text" : "DEFAULT";
  const charSql = charPath ? "'" + escapeSql(charPath) + "'::text" : "DEFAULT";
  const bgSql = bgPath ? "'" + escapeSql(bgPath) + "'::text" : "DEFAULT";

  const approvedSql = approved ? "true" : "false";

  sql +=
    "('" +
    idEscaped +
    "', '" +
    nameEscaped +
    "', '" +
    setIdEscaped +
    "'::public.rarity, '" +
    setIdEscaped +
    "'::text, '" +
    artPathEscaped +
    "'::text, " +
    depthSql +
    ", " +
    charSql +
    ", " +
    bgSql +
    ", " +
    tagsValue +
    ", " +
    approvedSql +
    ", " +
    alphaSql +
    ")";

  return sql;
}

function buildBannerSql(bannerId, bannerName) {
  const costSingle = 160;
  const costTen = 1600;

  if (!bannerId) return "";

  const idEscaped = bannerId.replace(/'/g, "''");
  const nameEscaped = bannerName.replace(/'/g, "''");

  let sql = "INSERT INTO public.banners ";
  sql += "(id, name, cost_single, cost_ten) ";
  sql += "VALUES ";
  sql += "('" + idEscaped + "', '" + nameEscaped + "', " + costSingle + ", " + costTen + ") ";
  sql += "ON CONFLICT (id) DO NOTHING;";

  return sql;
}

function buildBannerCardsSql(bannerId, cardIds) {
  if (!bannerId || cardIds.length === 0) return "";

  // Build VALUES list
  let values = "";
  for (let i = 0; i < cardIds.length; i += 1) {
    if (i > 0) values += ",\n  ";
    values +=
      "('" + bannerId + "', '" + cardIds[i].replace(/'/g, "''") + "')";
  }

  let sql = "INSERT INTO public.banner_cards ";
  sql += "(banner_id, card_id) ";
  sql += "VALUES ";
  sql += "\n  " + values + " ";
  sql += "ON CONFLICT (banner_id, card_id) DO NOTHING;";

  return sql;
}

// ---------------------------------------------------------------------------
// Main preparation logic
// ---------------------------------------------------------------------------

function prepareImport(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const target = args.target ?? join(resolve(HERE, "..", "shared", "art", "approved"));

  if (!existsSync(target)) {
    console.error("import-cards: folder not found: " + target);
    process.exit(1);
  }

  // Find card folders
  const folders = findCardFolders(target);
  if (folders.length === 0) {
    console.error("import-cards: no card.json found under " + target);
    process.exit(1);
  }

  // Load schema and validate all cards
  const schema = loadSchema(SCHEMA_PATH);
  const validationResults = validateCards(target, schema);

  // Separate valid from invalid.
  // The schema has additionalProperties: false, which flags 'name' and 'rating'
  // as unexpected. Cards whose only problems are those two are still treatable
  // for import — we strip those fields before SQL generation.
  const validCards = [];
  const invalidCards = [];
  const reservedUnexpected = new Set(["name", "rating"]);

  for (const { cardId, problems } of validationResults) {
    const hasOnlyReservedUnexpected = problems.length > 0
      && problems.every(p => {
        const msg = p.toLowerCase();
        return msg.includes("unexpected property") && reservedUnexpected.has(p.split(":")[0].trim().toLowerCase().replace("property", "").trim());
      });

    if (hasOnlyReservedUnexpected) {
      // Treat as valid — we'll strip name/rating before SQL generation
      validCards.push(cardId);
    } else if (problems.length === 0) {
      validCards.push(cardId);
    } else {
      invalidCards.push({ cardId, problems });
    }
  }

  // Check PNG layers for valid cards
  const layerResults = {};
  for (const dir of folders) {
    const folderName = basename(resolve(dir));
    const cardResult = validationResults.find(
      (r) => r.cardId === folderName || basename(resolve(dir)) === folderName,
    );
    if (!cardResult) continue;

    const manifestPath = join(dir, "card.json");
    let manifest;
    try {
      manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    } catch {
      continue;
    }

    const rarity = manifest.rarity;
    if (rarity && REQUIRED_LAYERS[rarity]) {
      layerResults[folderName] = checkLayers(dir, rarity);
    } else {
      layerResults[folderName] = [];
    }
  }

  // Collect card IDs for banner linking
  const cardIdList = validCards;

  // Build banner SQL
  const bannerSqlCmd = args.banner
    ? buildBannerSql(args.banner, args.bannerName || "KaT Alpha")
    : "";

  // Build banner_cards SQL
  const bannerCardsSqlCmd = args.banner && cardIdList.length > 0
    ? buildBannerCardsSql(args.banner, cardIdList)
    : "";

  // Generate cards SQL for non-imported valid cards
  const alpha = args.alpha;
  const cardsSql = [];

  for (const dir of folders) {
    const folderName = basename(resolve(dir));
    const cardResult = validationResults.find((r) => r.cardId === folderName);
    if (!cardResult) continue;

    const manifestPath = join(dir, "card.json");
    let manifest;
    try {
      manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    } catch {
      continue;
    }

    // Skip already-imported cards
    if (manifest.imported === true) {
      console.log("SKIP (already imported): " + folderName);
      continue;
    }

    // Strip fields that the schema marks as unexpected but that the image pipeline
    // adds. We keep character_name for SQL insertion; rating is informational only.
    const { name: _, rating: __, ...coreManifest } = manifest;

    // Check for layer problems
    const layerProblems = layerResults[folderName] || [];
    if (layerProblems.length > 0) {
      console.warn("LAYER PROBLEMS for " + folderName + ":");
      for (const p of layerProblems) console.warn("  - " + p);
    }

    try {
      const sql = buildCardSql(coreManifest, alpha);
      cardsSql.push(sql);
    } catch (error) {
      console.error("SQL ERROR for " + folderName + ": " + error.message);
    }
  }

  // -------------------------------------------------------------------------
  // Output report
  // -------------------------------------------------------------------------

  console.log("==============================================================");
  console.log(
    "          WAIFU CARD COLLECTOR — IMPORT PREPARATION REPORT",
  );
  console.log("==============================================================");

  console.log("\n--- Target ---------------------------------------------------");
  console.log("Directory: " + target);

  console.log("\n--- Arguments ------------------------------------------------");
  console.log("--alpha: " + args.alpha);
  console.log("--banner: " + (args.banner || "(not set)"));
  console.log("--banner-name: " + (args.bannerName || "not set"));

  console.log("\n--- Validation -----------------------------------------------");
  console.log("Total card folders found: " + folders.length);
  console.log("Valid against schema: " + validCards.length);
  console.log("Invalid against schema: " + invalidCards.length);
  console.log(
    "Already imported (skip): " + (folders.length - validCards.length - invalidCards.length),
  );

  if (invalidCards.length > 0) {
    console.log("\n--- Invalid manifests ---");
    for (const { cardId, problems } of invalidCards) {
      console.log("\n" + cardId + ":");
      for (const p of problems) console.log("  - " + p);
    }
  }

  if (Object.keys(layerResults).length > 0) {
    const layerIssues = [];
    for (const [folderName, problems] of Object.entries(layerResults)) {
      if (problems.length > 0) layerIssues.push([folderName, problems]);
    }
    if (layerIssues.length > 0) {
      console.log("\n--- Layer validation issues ---");
      for (const [folderName, problems] of layerIssues) {
        console.log("\n" + folderName + ":");
        for (const p of problems) console.log("  - " + p);
      }
    }
  }

  console.log("\n--- SQL Preparation ------------------------------------------");
  if (bannerSqlCmd) console.log("\n-- Banner insertion:");
  console.log(bannerSqlCmd);
  if (bannerCardsSqlCmd) console.log("\n-- Banner-card links:");
  console.log(bannerCardsSqlCmd);
  if (cardsSql.length > 0) {
    console.log("\n-- Card insertions:");
    for (let i = 0; i < cardsSql.length; i += 1) {
      console.log(
        "-- [" + (i + 1) + "/" + cardsSql.length + "] " + cardsSql[i].split("\n")[0],
      );
    }
    if (cardsSql.length > 1) {
      console.log("... (" + cardsSql.length + " total INSERT statements)");
    }
  } else {
    console.log(
      "\n-- No card INSERT statements generated (all cards already imported or invalid).",
    );
  }

  console.log("\n==============================================================");
  console.log(
    "  Review the SQL above. To apply, paste the statements into",
  );
  console.log(
    "  Supabase -> SQL Editor -> Run. Do not re-run import-cards on the same",
  );
  console.log(
    "  data without clearing 'imported' flags first.",
  );
  console.log("==============================================================");
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const invokedDirectly =
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  prepareImport();
  process.exit(0);
}

// Exports for testing
export { prepareImport, parseArgs, buildCardSql, buildBannerSql, buildBannerCardsSql, checkLayers, REQUIRED_LAYERS };