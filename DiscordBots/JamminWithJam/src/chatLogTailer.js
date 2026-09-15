import { open, stat } from "node:fs/promises";
import { EventEmitter } from "node:events";

/**
 * Polls a growing text file and emits one "line" event per new line
 * appended to it since the last poll. Written for Logs\WoWChatLog.txt, but
 * nothing here is WoW-specific.
 *
 * Polling, not fs.watch: whether the WoW client flushes chat log writes in
 * real time or only in bursts is not confirmed (Docs/JamminWithJam.md), and
 * a filesystem watch can miss or coalesce events across that uncertainty in
 * ways that are hard to notice. Reading the file's size on an interval is
 * slower in principle and correct regardless of how the writer buffers.
 *
 * Starts at the file's CURRENT size, not its beginning: a restart must not
 * replay a session's worth of old !jam lines as fresh triggers.
 */
export class ChatLogTailer extends EventEmitter {
  constructor(filePath, { pollIntervalMs = 750 } = {}) {
    super();
    this.filePath = filePath;
    this.pollIntervalMs = pollIntervalMs;
    this.offset = 0;
    this.carry = "";
    this.timer = null;
  }

  async start() {
    try {
      this.offset = (await stat(this.filePath)).size;
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
      this.offset = 0;
    }
    this.timer = setInterval(() => {
      this._poll().catch((err) => this.emit("error", err));
    }, this.pollIntervalMs);
    this.emit("started", { offset: this.offset });
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async _poll() {
    let size;
    try {
      size = (await stat(this.filePath)).size;
    } catch (err) {
      if (err.code === "ENOENT") return; // WoW has not created it (yet)
      throw err;
    }

    if (size < this.offset) {
      // Truncated or replaced under us: read from the top rather than
      // seeking past a file that has gone backwards.
      this.offset = 0;
      this.carry = "";
      this.emit("rotated");
    }
    if (size === this.offset) return;

    const handle = await open(this.filePath, "r");
    let text;
    try {
      const length = size - this.offset;
      const buf = Buffer.alloc(length);
      await handle.read(buf, 0, length, this.offset);
      text = buf.toString("utf8");
      this.offset = size;
    } finally {
      await handle.close();
    }

    const lines = (this.carry + text).split(/\r?\n/);
    // The split's last element is whatever comes after the final newline in
    // this chunk -- a partial line if the writer stopped mid-line, or "" if
    // it ended cleanly. Either way it is not a line yet.
    this.carry = lines.pop() ?? "";
    for (const line of lines) {
      if (line !== "") this.emit("line", line);
    }
  }
}
