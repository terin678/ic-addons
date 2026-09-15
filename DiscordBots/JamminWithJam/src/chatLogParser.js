/**
 * Parses one line of WoW's own Logs\WoWChatLog.txt (written by the client's
 * built-in `/chatlog` command) into { channel, sender, message, raw }, or
 * null when the line is not a chat line this bot cares about.
 *
 * NEEDS VERIFICATION AGAINST A REAL CLIENT. Blizzard does not publish the
 * exact format, and there was nothing to test it against while writing this
 * (see Docs/JamminWithJam.md "The bridge, and why it needs verifying" in the
 * main repo). What is here is written defensively against the handful of
 * shapes chat logging is reported to use, each covered by its own test
 * below. Once you have `/chatlog` on and a real captured line:
 *   1. Run `/jam play <id>` in game.
 *   2. Open Logs\WoWChatLog.txt and find the line it produced.
 *   3. Add it as a new case in test/chatLogParser.test.js and adjust the
 *      patterns below until that case (and every existing one) passes.
 * Everything downstream (commandRouter.js) only depends on the returned
 * shape, not on how it was extracted, so fixing this file is the entire fix.
 */

// WoWCombatLog.txt's confirmed leading timestamp shape, e.g. "9/14 20:15:32.123".
// If the chat log shares the same logging subsystem -- plausible, since both
// are enabled by a similarly named slash command and land in the same Logs
// folder -- it opens every line the same way.
const TIMESTAMP_RE = /^\d{1,2}\/\d{1,2}\s+\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\s+/;

// [Guild] Malexis: hello   |   [2. Trade] Malexis: hello   |   [Officer] Malexis: hello
const BRACKET_RE = /^\[(?<channel>[^\]]+)\]\s*(?<sender>[^:]+):\s*(?<message>.*)$/;

// Malexis says: hello   |   Malexis whispers: hello   |   Malexis yells: hello
const VERB_RE =
  /^(?<sender>[A-Za-z][\w'-]*)\s+(?<verb>says|whispers|yells|raid warns|party says|guild says|officer says)(?:\s+to\s+\S+)?\s*:\s*(?<message>.*)$/i;

const VERB_CHANNEL = {
  says: "say",
  whispers: "whisper",
  yells: "yell",
  "raid warns": "raid_warning",
  "party says": "party",
  "guild says": "guild",
  "officer says": "officer",
};

// Fallback: plain "Sender: message", the shape a bracketed channel name
// degrades to if this build omits it. Deliberately last and deliberately
// loose -- see the false-positive test below -- because everything more
// specific has already had its chance to match first.
const PLAIN_RE = /^(?<sender>[A-Za-z][\w'-]*):\s*(?<message>.*)$/;

/**
 * @param {string} line one line of WoWChatLog.txt, without its trailing newline
 * @returns {{channel: string|null, sender: string, message: string, raw: string}|null}
 */
export function parseChatLogLine(line) {
  if (typeof line !== "string") return null;
  const raw = line;
  const trimmed = line.trim();
  if (trimmed === "") return null;

  const body = trimmed.replace(TIMESTAMP_RE, "");

  let match = BRACKET_RE.exec(body);
  if (match) {
    const { channel, sender, message } = match.groups;
    return { channel: channel.trim(), sender: sender.trim(), message: message.trim(), raw };
  }

  match = VERB_RE.exec(body);
  if (match) {
    const { sender, verb, message } = match.groups;
    return {
      channel: VERB_CHANNEL[verb.toLowerCase()] ?? null,
      sender: sender.trim(),
      message: message.trim(),
      raw,
    };
  }

  match = PLAIN_RE.exec(body);
  if (match) {
    const { sender, message } = match.groups;
    return { channel: null, sender: sender.trim(), message: message.trim(), raw };
  }

  return null;
}

/**
 * Pure. Does a parsed line's message match `<prefix> <id>`? Returns the id,
 * lower-cased to match the addon's catalogue ids, or null.
 */
export function matchTrigger(parsedLine, prefix) {
  if (!parsedLine || typeof parsedLine.message !== "string") return null;
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`^${escaped}\\s+(\\S+)$`, "i");
  const match = re.exec(parsedLine.message.trim());
  return match ? match[1].toLowerCase() : null;
}
