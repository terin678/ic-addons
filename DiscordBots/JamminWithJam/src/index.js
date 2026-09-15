import "dotenv/config";
import { Client, GatewayIntentBits } from "discord.js";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { loadConfig } from "./config.js";
import { ChatLogTailer } from "./chatLogTailer.js";
import { parseChatLogLine } from "./chatLogParser.js";
import { decide } from "./commandRouter.js";
import { createCooldownState, recordFire } from "./cooldowns.js";
import { createVoicePlayer } from "./voicePlayer.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const token = process.env.DISCORD_TOKEN;
if (!token) {
  console.error("DISCORD_TOKEN is not set. Copy .env.example to .env and fill it in.");
  process.exit(1);
}

const config = loadConfig();
const cooldownState = createCooldownState();
const soundsDir = process.env.JAM_SOUNDS_DIR || path.join(__dirname, "..", "sounds");
const voicePlayer = createVoicePlayer({ soundsDir });

// A short ring buffer for /jamstatus, not a log file. Anything worth keeping
// belongs in the console output, which whoever runs the bot already has open.
const RECENT_MAX = 10;
const recent = [];
function noteRecent(line) {
  recent.unshift({ at: new Date(), line });
  recent.length = Math.min(recent.length, RECENT_MAX);
}

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates],
});

client.once("ready", async () => {
  console.log(`[jam] logged in as ${client.user.tag}`);

  const guild = await client.guilds.fetch(config.guildId);
  await voicePlayer.connect(config.voiceChannelId, config.guildId, guild.voiceAdapterCreator);
  console.log(`[jam] joined voice channel ${config.voiceChannelId} in ${guild.name}`);

  await guild.commands.create({
    name: "jamstatus",
    description: "JamminWithJam bot status: chat log, voice connection, recent sounds",
  });

  const tailer = new ChatLogTailer(config.chatLogPath);
  tailer.on("started", ({ offset }) => {
    console.log(`[jam] watching ${config.chatLogPath} from byte ${offset}`);
  });
  tailer.on("rotated", () => {
    console.log(`[jam] ${config.chatLogPath} shrank; reading from the top`);
  });
  tailer.on("error", (err) => {
    console.error("[jam] chat log tailer error:", err.message);
  });
  tailer.on("line", (rawLine) => {
    const parsed = parseChatLogLine(rawLine);
    if (!parsed) return;

    const outcome = decide(parsed, config, cooldownState, Date.now());
    if (!outcome) return; // not a trigger line; not worth a word

    if (outcome.skip) {
      console.log(`[jam] skipped: ${outcome.reason}`);
      noteRecent(`skipped: ${outcome.reason}`);
      return;
    }

    recordFire(cooldownState, outcome.play.id, Date.now());
    voicePlayer.enqueue(outcome.play.file);
    console.log(`[jam] ${outcome.sender} played "${outcome.play.id}" (${outcome.play.label})`);
    noteRecent(`${outcome.sender} played "${outcome.play.id}"`);
  });

  await tailer.start();
});

client.on("interactionCreate", async (interaction) => {
  if (!interaction.isChatInputCommand() || interaction.commandName !== "jamstatus") return;

  const lines = [
    `Voice: **${voicePlayer.connectionStatus}**, queue length **${voicePlayer.queueLength}**`,
    `Watching: \`${config.chatLogPath}\``,
    recent.length === 0
      ? "Nothing seen yet this session."
      : recent.map((r) => `${r.at.toLocaleTimeString()} — ${r.line}`).join("\n"),
  ];
  await interaction.reply({ content: lines.join("\n"), ephemeral: true });
});

client.login(token);
