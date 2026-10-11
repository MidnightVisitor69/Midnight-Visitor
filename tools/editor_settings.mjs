#!/usr/bin/env node
// editor_settings.mjs — Read/write Godot 4 editor_settings-4.7.tres keys.
// Used by tools/build_apk.ps1 and tested with `node --test`.
// Functions accept an optional `settingsPath` parameter; when omitted they fall back
// to process.env.APPDATA + "/Godot/editor_settings-4.7.tres".

import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

/**
 * Resolve the path to the Godot editor settings file.
 * Falls back to %APPDATA%/Godot/editor_settings-4.7.tres if no path given.
 */
function resolveSettingsPath(customPath) {
  if (customPath) return resolve(customPath);
  const apd = process.env.APPDATA || "";
  return resolve(apd, "Godot", "editor_settings-4.7.tres");
}

// ---------------------------------------------------------------------------
// Read the editor settings file. Returns lines as strings (without trailing newline).
// ---------------------------------------------------------------------------
function readSettings(settingsPath) {
  const path = resolveSettingsPath(settingsPath);
  if (!existsSync(path)) return [];
  const raw = readFileSync(path, "utf8");
  // Remove trailing empty line that results from the file's trailing \n
  const lines = raw.split("\n");
  if (lines.length > 1 && lines[lines.length - 1] === "") {
    lines.pop();
  }
  return lines;
}

// Write the full settings back to disk.
function writeSettings(lines, settingsPath) {
  const path = resolveSettingsPath(settingsPath);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, lines.join("\n") + "\n", "utf8");
}

// ---------------------------------------------------------------------------
// Find the line index for a given dotted key (e.g. "export/android/android_sdk_path").
// Returns -1 if not found.
function findKeyLineIndex(lines, key) {
  const pattern = new RegExp(`^${key}\\s*=`);
  for (let i = 0; i < lines.length; i += 1) {
    if (pattern.test(lines[i])) return i;
  }
  return -1;
}

/**
 * Ensure a key exists in the settings file, adding it if missing.
 * Does NOT mutate the file when called without a path that points to an existing
 * file — but when a path is given (or the default APPDATA path is used) it writes.
 * Returns the new line that was added/replaced.
 */
function ensureKey(key, value, settingsPath) {
  let lines = readSettings(settingsPath);
  let idx = findKeyLineIndex(lines, key);
  const newLine = `${key} = "${value}"`;

  if (idx >= 0) {
    lines[idx] = newLine;
  } else {
    // Append at the end (before any trailing empty line)
    if (lines[lines.length - 1] === "") {
      lines[lines.length - 1] = newLine;
    } else {
      lines.push(newLine);
    }
  }

  writeSettings(lines, settingsPath);
  return newLine;
}

/**
 * Replace the value of an existing key. Does nothing if the key is absent.
 * Returns the new line, or null if key not found.
 */
function replaceKey(key, value, settingsPath) {
  let lines = readSettings(settingsPath);
  let idx = findKeyLineIndex(lines, key);
  if (idx < 0) return null;

  lines[idx] = `${key} = "${value}"`;
  writeSettings(lines, settingsPath);
  return lines[idx];
}

/**
 * Get the current value of a key. Returns null if not found.
 */
function getKey(key, settingsPath) {
  let lines = readSettings(settingsPath);
  let idx = findKeyLineIndex(lines, key);
  if (idx < 0) return null;

  const line = lines[idx];
  // The format is key = "value" (with spaces around =), so match = "value"
  const match = line.match(/=\s*"(.*)"\s*$/);
  return match ? match[1] : null;
}

// ---------------------------------------------------------------------------
// Export functions for use in tests and the build script
// ---------------------------------------------------------------------------
export { resolveSettingsPath, readSettings, writeSettings, findKeyLineIndex, ensureKey, replaceKey, getKey };