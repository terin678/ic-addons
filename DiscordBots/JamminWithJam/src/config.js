import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG_PATH = path.join(__dirname, "..", "config.json");

/**
 * Loads and validates config.json. Thrown errors are meant to be read by a
 * human at startup, not caught, so they name the field and the file.
 */
export function loadConfig(configPath = process.env.JAM_CONFIG_PATH || DEFAULT_CONFIG_PATH) {
  let raw;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch (err) {
    if (err.code === "ENOENT") {
      throw new Error(
        `No config file at ${configPath}. Copy config.example.json to config.json and fill it in.`,
      );
    }
    throw err;
  }

  let config;
  try {
    config = JSON.parse(raw);
  } catch (err) {
    throw new Error(`${configPath} is not valid JSON: ${err.message}`);
  }

  return validateConfig(config, configPath);
}

const REQUIRED_STRINGS = ["chatLogPath", "triggerPrefix", "voiceChannelId", "guildId"];

export function validateConfig(config, sourceLabel = "config") {
  for (const key of REQUIRED_STRINGS) {
    if (typeof config[key] !== "string" || config[key].trim() === "") {
      throw new Error(`${sourceLabel}: "${key}" must be a non-empty string.`);
    }
  }

  if (!Number.isFinite(config.globalCooldownSec) || config.globalCooldownSec < 0) {
    throw new Error(`${sourceLabel}: "globalCooldownSec" must be a number >= 0.`);
  }

  if (!Array.isArray(config.officers)) {
    throw new Error(`${sourceLabel}: "officers" must be an array of WoW character names.`);
  }

  if (!Array.isArray(config.commands) || config.commands.length === 0) {
    throw new Error(`${sourceLabel}: "commands" must be a non-empty array.`);
  }

  const seen = new Set();
  for (const [i, cmd] of config.commands.entries()) {
    const where = `${sourceLabel}: commands[${i}]`;
    if (typeof cmd.id !== "string" || cmd.id.trim() === "") {
      throw new Error(`${where}: "id" must be a non-empty string.`);
    }
    if (seen.has(cmd.id)) {
      throw new Error(`${where}: duplicate id "${cmd.id}".`);
    }
    seen.add(cmd.id);
    if (typeof cmd.file !== "string" || cmd.file.trim() === "") {
      throw new Error(`${where}: "file" must be a non-empty string.`);
    }
    if (typeof cmd.label !== "string" || cmd.label.trim() === "") {
      throw new Error(`${where}: "label" must be a non-empty string.`);
    }
    if (!Number.isFinite(cmd.cooldownSec) || cmd.cooldownSec < 0) {
      throw new Error(`${where}: "cooldownSec" must be a number >= 0.`);
    }
    if (typeof cmd.officerOnly !== "boolean") {
      throw new Error(`${where}: "officerOnly" must be true or false.`);
    }
  }

  return config;
}
