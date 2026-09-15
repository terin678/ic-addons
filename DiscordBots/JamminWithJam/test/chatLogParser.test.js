import { test } from "node:test";
import assert from "node:assert/strict";
import { parseChatLogLine, matchTrigger } from "../src/chatLogParser.js";

// Every case here is a GUESS at what Logs\WoWChatLog.txt actually contains —
// see the file comment in chatLogParser.js. Once you have a real captured
// line, add it as a new case here (and adjust the parser) rather than
// trusting these.

test("bracketed channel: [Guild] Sender: message", () => {
  assert.deepEqual(parseChatLogLine("[Guild] Malexis: hello guild"), {
    channel: "Guild",
    sender: "Malexis",
    message: "hello guild",
    raw: "[Guild] Malexis: hello guild",
  });
});

test("bracketed channel with a number, e.g. a custom channel", () => {
  const parsed = parseChatLogLine("[2. Trade] Malexis: WTS stuff");
  assert.equal(parsed.channel, "2. Trade");
  assert.equal(parsed.sender, "Malexis");
  assert.equal(parsed.message, "WTS stuff");
});

test("a leading combat-log-style timestamp is stripped first", () => {
  const parsed = parseChatLogLine("9/14 20:15:32.123  [Guild] Malexis: !jam airhorn");
  assert.equal(parsed.channel, "Guild");
  assert.equal(parsed.sender, "Malexis");
  assert.equal(parsed.message, "!jam airhorn");
});

test("verb shape: Sender says: message", () => {
  const parsed = parseChatLogLine("Malexis says: !jam applause");
  assert.equal(parsed.channel, "say");
  assert.equal(parsed.sender, "Malexis");
  assert.equal(parsed.message, "!jam applause");
});

test("verb shape: whispers, case-insensitively", () => {
  const parsed = parseChatLogLine("Malexis WHISPERS: hey");
  assert.equal(parsed.channel, "whisper");
  assert.equal(parsed.message, "hey");
});

test("plain fallback: Sender: message with no bracket or verb", () => {
  const parsed = parseChatLogLine("Malexis: !jam airhorn");
  assert.equal(parsed.channel, null);
  assert.equal(parsed.sender, "Malexis");
  assert.equal(parsed.message, "!jam airhorn");
});

test("blank and whitespace-only lines are not chat lines", () => {
  assert.equal(parseChatLogLine(""), null);
  assert.equal(parseChatLogLine("   "), null);
  assert.equal(parseChatLogLine(null), null);
  assert.equal(parseChatLogLine(undefined), null);
});

test("a line with nothing resembling sender: message is null", () => {
  assert.equal(parseChatLogLine("Loading screen shown for realm hop"), null);
});

test("matchTrigger reads the id off a parsed message", () => {
  const parsed = { message: "!jam airhorn" };
  assert.equal(matchTrigger(parsed, "!jam"), "airhorn");
});

test("matchTrigger is case-insensitive on both prefix and id", () => {
  assert.equal(matchTrigger({ message: "!JAM AirHorn" }, "!jam"), "airhorn");
});

test("matchTrigger requires exactly one word after the prefix", () => {
  assert.equal(matchTrigger({ message: "!jam" }, "!jam"), null, "no id at all");
  assert.equal(matchTrigger({ message: "!jam airhorn now" }, "!jam"), null, "extra words");
});

test("matchTrigger ignores ordinary chat", () => {
  assert.equal(matchTrigger({ message: "does anyone have !jam?" }, "!jam"), null);
  assert.equal(matchTrigger(null, "!jam"), null, "no parsed line at all");
});

test("a custom prefix's regex characters are escaped, not interpreted", () => {
  assert.equal(matchTrigger({ message: "j.am airhorn" }, "j.am"), "airhorn");
  assert.equal(matchTrigger({ message: "jXam airhorn" }, "j.am"), null,
    "the dot in the prefix must be literal, not 'any character'");
});
