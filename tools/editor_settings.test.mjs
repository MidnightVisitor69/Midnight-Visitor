import { test } from "node:test";
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

import {
  resolveSettingsPath,
  readSettings,
  writeSettings,
  findKeyLineIndex,
  ensureKey,
  replaceKey,
  getKey,
} from "./editor_settings.mjs";

// Use a temporary test file under APPDATA so we don't clobber the real Godot settings.
const APPDATA = process.env.APPDATA || "";
const TEST_DIR = resolve(APPDATA, "Godot", "test_settings");
const TEST_SETTINGS = resolve(TEST_DIR, "editor_settings_test-4.7.tres");

function resetTestSettings() {
  if (existsSync(TEST_SETTINGS)) {
    try { require("node:fs").unlinkSync(TEST_SETTINGS); } catch {}
  }
  if (existsSync(TEST_DIR)) {
    try { require("node:fs").rmdirSync(TEST_DIR); } catch {}
  }
  mkdirSync(TEST_DIR, { recursive: true });
}

function setupTestFile(lines = []) {
  writeFileSync(TEST_SETTINGS, lines.join("\n") + "\n", "utf8");
}

// ---------------------------------------------------------------------------
// Test: ensureKey adds a missing key using a custom path
// ---------------------------------------------------------------------------
test("ensureKey adds a missing key with custom path", () => {
  resetTestSettings();
  setupTestFile([]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  ensureKey("export/android/android_sdk_path", "E:/AI/Tools/Android/sdk", path);

  const result = readSettings(path);
  assert.ok(
    result.some((l) => l.includes("export/android/android_sdk_path = \"E:/AI/Tools/Android/sdk\"")),
    "ensureKey must add the key to the settings file",
  );
});

// ---------------------------------------------------------------------------
// Test: ensureKey replaces an existing key using a custom path
// ---------------------------------------------------------------------------
test("ensureKey replaces an existing key with custom path", () => {
  resetTestSettings();
  setupTestFile([
    'export/android/android_sdk_path = "old/path"',
    "export/other/something = true",
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  ensureKey("export/android/android_sdk_path", "E:/AI/Tools/Android/sdk new", path);

  const result = readSettings(path);
  const sdkLine = result.find((l) => l.includes("android_sdk_path"));
  assert.equal(sdkLine, 'export/android/android_sdk_path = "E:/AI/Tools/Android/sdk new"',
    "ensureKey must replace the existing key value");
  assert.ok(
    result.some((l) => l.includes('export/other/something = true')),
    "ensureKey must leave other lines untouched",
  );
});

// ---------------------------------------------------------------------------
// Test: ensureKey leaves other lines untouched when adding a new key
// ---------------------------------------------------------------------------
test("ensureKey leaves other lines untouched when adding a second key", () => {
  resetTestSettings();
  setupTestFile([
    'export/android/android_sdk_path = "old/path"',
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  ensureKey("export/android/java_sdk_path", "E:/AI/Tools/jdk17", path);

  const result = readSettings(path);
  const count = result.filter((l) => l.includes("export/android")).length;
  assert.equal(count, 2, "ensureKey must add the new key without removing the old one");
  assert.ok(
    result.some((l) => l.includes('export/android/android_sdk_path = "old/path"')),
    "old key must remain",
  );
  assert.ok(
    result.some((l) => l.includes('export/android/java_sdk_path = "E:/AI/Tools/jdk17"')),
    "new key must be present",
  );
});

// ---------------------------------------------------------------------------
// Test: replaceKey replaces an existing key, does nothing if absent
// ---------------------------------------------------------------------------
test("replaceKey replaces existing key with custom path", () => {
  resetTestSettings();
  setupTestFile([
    'export/android/android_sdk_path = "old/path"',
    'export/android/java_sdk_path = "old/jdk"',
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  const replaced = replaceKey("export/android/android_sdk_path", "E:/AI/Tools/Android/sdk", path);

  assert.equal(replaced, 'export/android/android_sdk_path = "E:/AI/Tools/Android/sdk"',
    "replaceKey must return the new line");
  const result = readSettings(path);
  assert.equal(
    result[0],
    'export/android/android_sdk_path = "E:/AI/Tools/Android/sdk"',
    "replaceKey must replace the value",
  );
});

test("replaceKey does nothing when key is absent with custom path", () => {
  resetTestSettings();
  setupTestFile([
    'export/other/key = true',
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  const replaced = replaceKey("export/android/android_sdk_path", "some/path", path);

  assert.equal(replaced, null, "replaceKey must return null when key not found");
  const result = readSettings(path);
  assert.equal(result.length, 1, "file must not be modified");
  assert.ok(
    result[0].includes('export/other/key = true'),
    "original line must remain",
  );
});

// ---------------------------------------------------------------------------
// Test: getKey returns the value or null
// ---------------------------------------------------------------------------
test("getKey returns the value of a key with custom path", () => {
  resetTestSettings();
  setupTestFile([
    'export/android/android_sdk_path = "E:/AI/Tools/Android/sdk"',
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  const val = getKey("export/android/android_sdk_path", path);
  assert.equal(val, "E:/AI/Tools/Android/sdk", "getKey must return the stored value");
});

test("getKey returns null for missing key with custom path", () => {
  resetTestSettings();
  setupTestFile([]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  const val = getKey("export/android/android_sdk_path", path);
  assert.equal(val, null, "getKey must return null for a missing key");
});

// ---------------------------------------------------------------------------
// Test: ensureKey with empty file adds the first key using custom path
// ---------------------------------------------------------------------------
test("ensureKey works on completely empty file with custom path", () => {
  resetTestSettings();
  setupTestFile([]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  ensureKey("export/android/android_sdk_path", "E:/AI/Tools/Android/sdk", path);

  const result = readSettings(path);
  assert.equal(result.length, 1, "must have exactly one line");
  assert.ok(
    result[0].includes("export/android/android_sdk_path"),
    "must contain the added key",
  );
});

// ---------------------------------------------------------------------------
// Test: ensureKey appends new key after existing keys without clobbering
// ---------------------------------------------------------------------------
test("ensureKey appends new key after existing keys with custom path", () => {
  resetTestSettings();
  setupTestFile([
    'export/android/android_sdk_path = "E:/AI/Tools/Android/sdk"',
    'export/other/feature = false',
  ]);

  const path = resolveSettingsPath(TEST_SETTINGS);
  ensureKey("export/android/java_sdk_path", "E:/AI/Tools/jdk17", path);

  const result = readSettings(path);
  assert.equal(result.length, 3, "must have 3 lines total");
  assert.ok(
    result[0].includes("android_sdk_path"),
    "first key must be preserved",
  );
  assert.ok(
    result[1].includes("export/other/feature"),
    "middle key must be preserved",
  );
  assert.ok(
    result[2].includes("java_sdk_path"),
    "new key must be appended at the end",
  );
});