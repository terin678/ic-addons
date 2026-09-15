import { test } from "node:test";
import assert from "node:assert/strict";
import { validateConfig } from "../src/config.js";

function baseConfig(overrides = {}) {
  return {
    chatLogPath: "C:\\WoW\\Logs\\WoWChatLog.txt",
    triggerPrefix: "!jam",
    guildId: "1",
    voiceChannelId: "2",
    globalCooldownSec: 5,
    officers: ["Malexis"],
    commands: [
      { id: "airhorn", label: "Air Horn", file: "airhorn.mp3", officerOnly: false, cooldownSec: 20 },
    ],
    ...overrides,
  };
}

test("a well-formed config passes through unchanged", () => {
  const config = baseConfig();
  assert.equal(validateConfig(config), config);
});

test("a missing required string is refused, naming the field", () => {
  const config = baseConfig({ voiceChannelId: "" });
  assert.throws(() => validateConfig(config), /voiceChannelId/);
});

test("commands must be a non-empty array", () => {
  assert.throws(() => validateConfig(baseConfig({ commands: [] })), /commands/);
  assert.throws(() => validateConfig(baseConfig({ commands: "airhorn" })), /commands/);
});

test("a duplicate command id is refused", () => {
  const config = baseConfig({
    commands: [
      { id: "airhorn", label: "A", file: "a.mp3", officerOnly: false, cooldownSec: 1 },
      { id: "airhorn", label: "B", file: "b.mp3", officerOnly: false, cooldownSec: 1 },
    ],
  });
  assert.throws(() => validateConfig(config), /duplicate id/);
});

test("a command missing officerOnly is refused rather than defaulted", () => {
  // Silently defaulting this to false would make a mistyped config file
  // open an officer-only sound to the whole guild.
  const config = baseConfig({
    commands: [{ id: "airhorn", label: "A", file: "a.mp3", cooldownSec: 1 }],
  });
  assert.throws(() => validateConfig(config), /officerOnly/);
});

test("a negative cooldown is refused", () => {
  const config = baseConfig({
    commands: [{ id: "airhorn", label: "A", file: "a.mp3", officerOnly: false, cooldownSec: -1 }],
  });
  assert.throws(() => validateConfig(config), /cooldownSec/);
});
