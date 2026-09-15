import { test } from "node:test";
import assert from "node:assert/strict";
import { createCooldownState, secondsUntilReady, recordFire } from "../src/cooldowns.js";

test("a fresh state is ready for everything", () => {
  const state = createCooldownState();
  assert.equal(secondsUntilReady(state, "airhorn", 20, 5, Date.now()), 0);
});

test("per-command cooldown counts down from the last fire", () => {
  const state = createCooldownState();
  const t0 = 1_000_000;
  recordFire(state, "airhorn", t0);
  assert.equal(secondsUntilReady(state, "airhorn", 20, 0, t0 + 5_000), 15);
  assert.equal(secondsUntilReady(state, "airhorn", 20, 0, t0 + 20_000), 0);
  assert.equal(secondsUntilReady(state, "airhorn", 20, 0, t0 + 99_000), 0, "never negative");
});

test("the global cooldown blocks a DIFFERENT command too", () => {
  const state = createCooldownState();
  const t0 = 1_000_000;
  recordFire(state, "airhorn", t0);
  // applause has its own (shorter) per-command cooldown of 0, but the
  // global 5s since ANY sound played still applies.
  assert.equal(secondsUntilReady(state, "applause", 0, 5, t0 + 2_000), 3);
});

test("whichever cooldown is longer wins", () => {
  const state = createCooldownState();
  const t0 = 1_000_000;
  recordFire(state, "wipesiren", t0);
  assert.equal(secondsUntilReady(state, "wipesiren", 30, 5, t0 + 10_000), 20,
    "the 30s per-command cooldown outlasts the 5s global one");
});

test("firing one command does not reset another command's own cooldown", () => {
  const state = createCooldownState();
  const t0 = 1_000_000;
  recordFire(state, "airhorn", t0);
  recordFire(state, "applause", t0 + 1_000);
  // airhorn's own per-command timer still started at t0, only the shared
  // global timer moved to t0 + 1000.
  assert.equal(secondsUntilReady(state, "airhorn", 20, 0, t0 + 19_500), 0.5);
});
