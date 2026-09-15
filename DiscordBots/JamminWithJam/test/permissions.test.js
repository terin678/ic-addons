import { test } from "node:test";
import assert from "node:assert/strict";
import { isOfficerAllowed } from "../src/permissions.js";

test("an officer on the list is allowed", () => {
  assert.equal(isOfficerAllowed(["Malexis", "Threnody"], "Malexis"), true);
});

test("names are compared case-insensitively", () => {
  assert.equal(isOfficerAllowed(["Malexis"], "malexis"), true);
  assert.equal(isOfficerAllowed(["malexis"], "Malexis"), true);
});

test("someone not on the list is refused", () => {
  assert.equal(isOfficerAllowed(["Malexis"], "RandomGuildie"), false);
});

test("an empty or missing list refuses everyone", () => {
  assert.equal(isOfficerAllowed([], "Malexis"), false);
  assert.equal(isOfficerAllowed(undefined, "Malexis"), false);
});

test("an empty sender name is never a match", () => {
  assert.equal(isOfficerAllowed(["Malexis", ""], ""), false);
});
