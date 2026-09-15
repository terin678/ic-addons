# Jammin' With Jam

A guild soundboard: click a button in game, and a sound plays in the guild's Discord voice
channel a moment later.

The problem it solves is not "how do we play a sound" — Discord already has soundboards. It
is that nobody wants to alt-tab out of a boss fight to reach one. This puts the trigger
inside the game, where your hands already are.

**The addon cannot talk to Discord.** No WoW addon can open a network connection or write an
arbitrary file to disk; SavedVariables is the only thing an addon can persist, and it is only
written at logout. So the whole bridge is a chat line: the addon sends `!jam <id>` to a chat
channel, and a companion program — not part of the addon, not running inside WoW — watches
this client's own chat log file for that line and plays the matching sound in Discord.
Nothing you click here makes a sound by itself.

## Install

**The addon:**

```powershell
.\scripts\deploy.ps1 -Flavor anniversary -Addon JamminWithJam
```

That links ICLibs alongside it, because JamminWithJam lists it under `## Dependencies`. Then
restart the client (a fresh addon needs one; `/reload` is not enough — see
CODING_STANDARDS.md) and `/jam` opens the window.

**The bot:** lives outside this addon entirely, at
[`DiscordBots/JamminWithJam`](../DiscordBots/JamminWithJam). Its own
[README](../DiscordBots/JamminWithJam/README.md) has the setup: a Discord bot token, a voice
channel id, and turning on WoW's own chat logging. It has to run on the same PC as the WoW
client, because it reads that client's chat log file straight off disk.

## Quick start

1. Set up and start the bot first (its README), on the PC that is actually logged into WoW.
2. In game, `/jam` opens the soundboard. Click **Play** next to a sound.
3. That sends `!jam <id>` to the channel set on the Settings — no, there is no Settings tab
   yet; the channel is `GUILD` by default, changed in `Core.lua`'s `Defaults.settings.channel`
   until this addon has a page for it. The bot's console should print that it saw the line and
   is playing the sound within a second or two.

If nothing happens on the Discord side, work backwards: did the addon's own **Sounds** tab say
`ready` before you clicked, and `sent: <name>` in the chat frame after? Then the problem is
downstream of the addon — check the bot's own console output and its README's troubleshooting
section, not this one.

## Who may do what

One sound in the starting catalogue (`wipesiren`) is marked officer-only. Authority is a
guild rank threshold, and `rankIndex 0` is the guild master — a **larger** number is a
**lower** rank, so `officerRankIndex` is a ceiling: that rank and every one above it (every
smaller number) may play a locked sound.

| Setting | Default | Means |
| --- | --- | --- |
| `officerRankIndex` | 1 | This rank or better may play an officer-only sound |

**This addon-side check is a courtesy, not security.** Anyone can type `!jam wipesiren`
into guild chat by hand regardless of what the addon shows them, so the *real* gate has to
live in the bot: its `config.json` carries the list of character names allowed to trigger an
officer-only command, and that is what actually decides whether the sound plays. Greying the
button here just means a non-officer is not invited to try.

## The window

**Sounds** is the whole point: one row per catalogue entry, its status (`ready`, `officers
only`, or `on cooldown for Ns`), and a Play button that is disabled exactly when the status
says why. The cooldown shown is this character's own — see below, it is not shared with the
rest of the guild.

**Log** is what the addon has sent and skipped, same shape as every other addon here.

**About** reports client API availability and the test suite's last result.

## The catalogue and the bot's config have to agree, by hand

`Sounds.lua`'s `CATALOGUE` table and the bot's `config.json` are two files in two different
languages with no shared storage. An id added to one and not the other sends a chat line
nobody is listening for, or configures a sound nothing in the addon offers a button for. There
is no linter across the two — keep them in step when you add or rename a sound.

## Commands

| Command | Effect |
| --- | --- |
| `/jam` | Open or close the window |
| `/jam play <id>` | Send the chat trigger for that sound; same as clicking Play |
| `/jam list` | Print every sound id, and which are officer-only |
| `/jam log [n]` | Print the last n log lines |
| `/jam probe` | Report which client APIs this build has |
| `/jam status` | One line per part of the addon |
| `/jam test` | Run the test suite |
| `/jam enable` / `disable` | Master switch |
| `/jam out [n]` | Print to ChatFrame n |
| `/jam reset [settings\|log\|all]` | Restore defaults |
| `/jam version` | Addon and library versions |

One key binding under **JamminWithJam**: open or close the window.

## What the client will not let it do

**A cooldown here is per character, not per guild.** `ns.cdb.cooldowns` is SavedVariables**Per**
**Character**, so two different players — or two alts on the same account — can each fire the
same sound back to back; only the same character firing it twice in a row is throttled here.
The bot enforces a second, shared cooldown across everyone for exactly this reason: it is the
only side that can see every player's triggers at once.

**A public channel message needs a hardware event.** `SendChatMessage` to `GUILD` and similar
channels only goes out from a keypress or a click on this client (see
`.claude/skills/wow-addon-dev/client-api.md`), which is why `Sounds.Fire` is only ever called
from the Play button or a typed `/jam play` — never from a timer.

**The addon cannot confirm the bot heard it.** There is no reply path. `/jam play` says
`sent: <name>` the moment `SendChatMessage` returns, which only means the line went into your
own chat frame — not that `/chatlog` is on, that the bot is running, or that it matched the
line. Confirming the whole chain is a bot-side problem; see its README.

## The bridge, and why it needs verifying

WoW has a built-in `/chatlog` command that appends every chat line the client displays to
`Logs\WoWChatLog.txt`, next to `WoWCombatLog.txt`. The bot tails that file. This is the same
kind of mechanism Warcraft Logs' live-logging uses for the combat log, and it needs no
modification to the client and no third-party injection — it is a feature Blizzard ships.

What is **not** independently confirmed is the exact line format `/chatlog` writes (timestamp
layout, how a channel and sender are represented) — public documentation of it is thin. The
bot's parser (`DiscordBots/JamminWithJam/src/chatLogParser.js`) is written defensively against
a couple of plausible shapes and covered by its own tests, but the one test that matters is a
real one: turn `/chatlog` on, click Play in game, and open `WoWChatLog.txt` to see what an
actual line looks like. If the bot's console reports it never saw the trigger, this is almost
certainly why — see the bot's README for how to fix the parser once you have a real sample.

## Disclaimer

Enabling `/chatlog` writes **everyone's** chat that reaches your screen to a plain text file
on your disk, not just `!jam` lines — that is how the built-in feature works, and this addon
has no way to log a narrower slice of it. Treat that file the way you would any other record
of guild chat, and clear it out if you are not comfortable keeping it around. The Discord
bot's own token belongs in its `.env` file, kept out of source control (see its README) — it
is a credential, and anyone who has it can act as your bot.
