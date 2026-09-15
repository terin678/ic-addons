# JamminWithJam bot

The other half of the [JamminWithJam](../../AddonProjects/anniversary/JamminWithJam) WoW
addon. The addon cannot open a network connection or talk to Discord — no WoW addon can —
so this is a separate Node program that:

1. Watches this PC's own WoW chat log file for a line like `!jam airhorn`.
2. Checks who sent it against a cooldown and, for locked sounds, an officer list.
3. Plays the matching sound file in a Discord voice channel.

It has to run **on the same PC that is logged into WoW**, because step 1 reads a file off
that PC's own disk. It does not need to run on the PC of everyone who wants to hear the
sound — only whoever is triggering it, and everyone in the Discord voice channel hears the
result.

## Setup

### 1. Turn on WoW's chat logging

In game, type:

```
/chatlog
```

This toggles a client feature (not an addon) that appends every chat line you can see to
`Logs\WoWChatLog.txt`, next to `WoWCombatLog.txt`, inside your WoW installation folder. It
stays on across sessions until you type `/chatlog` again. **See "Verifying the log format"
below before assuming this works — it almost certainly needs one adjustment.**

### 2. Create a Discord bot and invite it

1. [Discord Developer Portal](https://discord.com/developers/applications) → New
   Application → **Bot** tab → Reset Token, copy it.
2. No privileged gateway intents are needed — this bot only joins voice and reads a local
   file, it does not read Discord messages.
3. OAuth2 → URL Generator → scope `bot`, permissions **Connect** and **Speak** → open the
   generated URL and invite it to your server.
4. Right-click your server icon → Copy Server ID, and right-click the voice channel you want
   sounds to play in → Copy Channel ID. (Enable Developer Mode in Discord's settings if you
   do not see those options.)

### 3. Configure the bot

```powershell
cd DiscordBots/JamminWithJam
npm install
copy .env.example .env
copy config.example.json config.json
```

Edit `.env`: paste the bot token into `DISCORD_TOKEN`.

Edit `config.json`:

- `chatLogPath` — the full path to `WoWChatLog.txt` from step 1.
- `guildId` / `voiceChannelId` — the ids from step 2.
- `officers` — WoW character names (not Discord names) allowed to trigger an
  `officerOnly` command.
- `commands` — must match the addon's own catalogue; see "Keeping the two catalogues in
  step" below.

### 4. Add sound files

Drop the audio files `config.json`'s `commands[].file` values point at into `sounds/`.
Nothing is shipped there — pick your own clips. `sounds/README.md` has the detail.

### 5. Run it

```powershell
npm start
```

You should see it log in, join the voice channel, and start watching the chat log file.
Leave it running; it reconnects on its own if Discord drops the voice connection.

## Verifying the log format

**This is the one step that is not guaranteed to work out of the box.** Blizzard does not
publish the exact line format `/chatlog` writes, and there was nothing to test the parser in
`src/chatLogParser.js` against while building this. It is written to handle a few plausible
shapes and each is covered by a test in `test/chatLogParser.test.js`, but "plausible" is not
"confirmed."

To check:

1. Start the bot (`npm start`) and watch its console.
2. In game, click Play on the addon's Sounds tab, or type `/jam play airhorn`.
3. Watch the console. `[jam] <name> played "airhorn" (...)` means it worked — you're done.
4. If ten seconds pass with nothing, open `WoWChatLog.txt` yourself and look at the last
   line. Compare it against the shapes in `chatLogParser.js`'s comment. Add your real line
   as a new case in `test/chatLogParser.test.js`, run `npm test`, and adjust the regular
   expressions in `chatLogParser.js` until it (and every existing case) passes. That file's
   comment says exactly what to change and why.

## Keeping the two catalogues in step

`AddonProjects/anniversary/JamminWithJam/Sounds.lua`'s `CATALOGUE` table and this bot's
`config.json` are two files in two different languages with no shared storage — nothing
checks that they agree. An id in one and not the other means either a button that sends a
chat line nobody is listening for, or a `config.json` entry nothing in the addon offers a
button for. Add or rename a sound in both places at once.

## Slash command

`/jamstatus` in Discord reports the voice connection state, how many sounds are queued, and
the last ten things the bot has seen — useful for "is this even running" without needing
console access.

## Why these dependencies

- **`opusscript`**, not `@discordjs/opus` — pure JavaScript, so nothing here needs a C++
  build toolchain on a guildmate's Windows machine just to install this bot.
- **`tweetnacl`**, not `sodium-native` — same reason: voice connections need an encryption
  library, and this one has no native build step either.
- **`ffmpeg-static`** bundles an ffmpeg binary so nobody has to install ffmpeg separately;
  `src/voicePlayer.js` points `@discordjs/voice`'s transcoder at it directly.

If playback CPU usage ever matters (it should not, for occasional short clips), swapping
`opusscript` for `@discordjs/opus` is a drop-in change in `package.json` — nothing else
references it by name.

## Tests

```powershell
npm test
```

Runs on Node's built-in test runner — no extra dependency for that. `chatLogTailer.test.js`
uses real temporary files and real timers rather than mocking the filesystem, because the
behaviour worth checking (only new bytes, coping with a file that does not exist yet,
recovering from a file that shrinks) is exactly what a mock would paper over.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Bot logs in but never joins voice | Wrong `guildId`/`voiceChannelId`, or the bot lacks Connect/Speak on that channel |
| Bot joins voice but chat triggers do nothing | See "Verifying the log format" above |
| Console says `unknown sound id` | The addon's `Sounds.lua` and this bot's `config.json` have drifted apart |
| Console says `is not allowed to play officer-only` | The sender's WoW character name is not in `config.json`'s `officers` list (case-insensitive, but must otherwise match exactly) |
| `npm start` exits immediately naming a config field | `config.json` failed validation; the error names the field |
