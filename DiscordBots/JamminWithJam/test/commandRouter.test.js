import { test } from "node:test";
import assert from "node:assert/strict";
import { decide } from "../src/commandRouter.js";
import { createCooldownState, recordFire } from "../src/cooldowns.js";

const config = {
  triggerPrefix: "!jam",
  globalCooldownSec: 5,
  officers: ["Malexis"],
  commands: [
    { id: "airhorn", label: "Air Horn", file: "airhorn.mp3", officerOnly: false, cooldownSec: 20 },
    { id: "wipesiren", label: "Wipe Siren", file: "wipesiren.mp3", officerOnly: true, cooldownSec: 30 },
  ],
};

test("a line that is not a trigger at all is ignored, not skipped", () => {
  const parsed = { sender: "Anyone", message: "does anyone have wipesiren?", channel: "guild" };
  assert.equal(decide(parsed, config, createCooldownState(), Date.now()), null);
});

test("a known, unlocked, off-cooldown command plays", () => {
  const parsed = { sender: "RandomGuildie", message: "!jam airhorn", channel: "guild" };
  const result = decide(parsed, config, createCooldownState(), Date.now());
  assert.equal(result.play.id, "airhorn");
  assert.equal(result.sender, "RandomGuildie");
});

test("an unknown id is a skip, not a crash", () => {
  const parsed = { sender: "RandomGuildie", message: "!jam nosuchsound", channel: "guild" };
  const result = decide(parsed, config, createCooldownState(), Date.now());
  assert.equal(result.skip, true);
  assert.match(result.reason, /unknown sound id/);
});

test("an officer-only command refuses a non-officer", () => {
  const parsed = { sender: "RandomGuildie", message: "!jam wipesiren", channel: "guild" };
  const result = decide(parsed, config, createCooldownState(), Date.now());
  assert.equal(result.skip, true);
  assert.match(result.reason, /not allowed/);
});

test("an officer-only command allows an officer", () => {
  const parsed = { sender: "Malexis", message: "!jam wipesiren", channel: "guild" };
  const result = decide(parsed, config, createCooldownState(), Date.now());
  assert.equal(result.play.id, "wipesiren");
});

test("a command still on cooldown is a skip naming the id", () => {
  const state = createCooldownState();
  const now = Date.now();
  recordFire(state, "airhorn", now);
  const parsed = { sender: "RandomGuildie", message: "!jam airhorn", channel: "guild" };
  const result = decide(parsed, config, state, now + 1000);
  assert.equal(result.skip, true);
  assert.match(result.reason, /airhorn.*cooldown/);
});

test("unknown id is reported before the cooldown or permission check", () => {
  // Widest reason first, same rule as the addon's Sounds.BlockReason: the
  // reason shown must not depend on which check happened to run.
  const state = createCooldownState();
  recordFire(state, "nosuchsound", Date.now());
  const parsed = { sender: "RandomGuildie", message: "!jam nosuchsound", channel: "guild" };
  const result = decide(parsed, config, state, Date.now());
  assert.match(result.reason, /unknown sound id/);
});
