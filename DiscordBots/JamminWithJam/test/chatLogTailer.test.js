import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, appendFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { ChatLogTailer } from "../src/chatLogTailer.js";

// A real file on a real timer, not a mock: the behaviour worth checking is
// exactly the part a mock would paper over -- reading only what was
// appended, and coping with a file that does not exist yet.
const POLL_MS = 30;

async function withTempFile(run) {
  const dir = await mkdtemp(path.join(tmpdir(), "jam-tailer-"));
  const filePath = path.join(dir, "WoWChatLog.txt");
  try {
    await run(filePath);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function waitForLines(tailer, count, timeoutMs = 2000) {
  return new Promise((resolve, reject) => {
    const lines = [];
    const timer = setTimeout(() => reject(new Error(`timed out waiting for ${count} line(s)`)), timeoutMs);
    tailer.on("line", (line) => {
      lines.push(line);
      if (lines.length >= count) {
        clearTimeout(timer);
        resolve(lines);
      }
    });
  });
}

test("only lines appended AFTER start are emitted", async () => {
  await withTempFile(async (filePath) => {
    await writeFile(filePath, "old line, before the bot started\n");

    const tailer = new ChatLogTailer(filePath, { pollIntervalMs: POLL_MS });
    await tailer.start();
    try {
      const pending = waitForLines(tailer, 1);
      await appendFile(filePath, "[Guild] Malexis: !jam airhorn\n");
      const lines = await pending;
      assert.deepEqual(lines, ["[Guild] Malexis: !jam airhorn"]);
    } finally {
      tailer.stop();
    }
  });
});

test("a line split across two writes is only emitted once it is complete", async () => {
  await withTempFile(async (filePath) => {
    await writeFile(filePath, "");
    const tailer = new ChatLogTailer(filePath, { pollIntervalMs: POLL_MS });
    await tailer.start();
    try {
      const pending = waitForLines(tailer, 1);
      await appendFile(filePath, "[Guild] Malexis: !jam air");
      await new Promise((r) => setTimeout(r, POLL_MS * 3));
      await appendFile(filePath, "horn\n");
      const lines = await pending;
      assert.deepEqual(lines, ["[Guild] Malexis: !jam airhorn"]);
    } finally {
      tailer.stop();
    }
  });
});

test("starting before the file exists picks it up once created", async () => {
  await withTempFile(async (filePath) => {
    const tailer = new ChatLogTailer(filePath, { pollIntervalMs: POLL_MS });
    await tailer.start();
    try {
      const pending = waitForLines(tailer, 1);
      await writeFile(filePath, "[Guild] Malexis: !jam airhorn\n");
      const lines = await pending;
      assert.deepEqual(lines, ["[Guild] Malexis: !jam airhorn"]);
    } finally {
      tailer.stop();
    }
  });
});

test("a file that shrinks (truncated or replaced) is read from the top again", async () => {
  await withTempFile(async (filePath) => {
    await writeFile(filePath, "a very long first line that will not appear again\n");
    const tailer = new ChatLogTailer(filePath, { pollIntervalMs: POLL_MS });
    await tailer.start();
    try {
      const rotated = new Promise((resolve) => tailer.once("rotated", resolve));
      const pending = waitForLines(tailer, 1);
      await writeFile(filePath, "[Guild] Malexis: !jam airhorn\n");
      await rotated;
      const lines = await pending;
      assert.deepEqual(lines, ["[Guild] Malexis: !jam airhorn"]);
    } finally {
      tailer.stop();
    }
  });
});
