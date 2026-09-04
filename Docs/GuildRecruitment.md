# Guild Recruitment

One recruitment message the raid leaders set and every officer sends, kept in step across
the guild, with a log of who barked when.

The problem it solves: two raid teams, every raid officer recruiting for both, everyone
typing their own line into a channel. Nobody knows who posted last, so two officers post
four minutes apart, and the wording drifts until the two teams are advertised differently by
different people.

## Install

```powershell
.\scripts\deploy.ps1 -Flavor anniversary -Addon GuildRecruitment
```

That links ICLibs alongside it, because GuildRecruitment lists it under `## Dependencies`.
Then `/reload`, and `/gr` opens the window.

## Quick start

1. A raid leader opens the **Teams** tab and says what each team is short of. Roles and
   classes are free text — "Feral Druid" is a thing you can ask for.
2. They open **Message**, write the line, and press **Save and push**. Every officer who is
   online and running the addon takes it within a few seconds.
3. Any officer opens **Bark**, reads the line, and presses **Send now**.

Barking is off by default. Turning the reminder on means a sound and a chat line when it is
time; it does not send anything by itself, and it cannot (see below).

## Who may do what

Authority is a guild rank threshold, and `rankIndex 0` is the guild master — a **larger**
number is a **lower** rank, so both settings are ceilings.

| Setting | Default | Means |
| --- | --- | --- |
| Raid leaders | rank 2 or better | may change the message and the teams, and push them |
| Officers | rank 4 or better | may send the message |

**The two numberings do not agree.** The guild window lists ranks from 1; the game reports
them from 0, and this addon uses the game's, so the guild master is 0 here and 1 there.
Impulse Control's raid leaders are the guild master plus the two team leaders, which is
0, 1 and 2 in this numbering and 1, 2 and 3 in the guild window's -- hence the default of 2.
The Settings tab prints your guild's own name for whichever rank a threshold lands on, so
you never have to work out which numbering a screen is using.

Only the guild master can move the thresholds, on the **Settings** tab.

**This is a local setting, and that is a real limitation.** No addon has server-side
authority. Each client decides for itself whose messages it will accept, so an officer whose
threshold disagrees with yours will accept messages yours ignores. The **Officers** tab shows
who is holding which revision, which is how a mismatch becomes visible instead of mysterious.

## The window

**Bark** is the tab every officer lives on. The exact line that will go out is shown right
above the button that sends it — deliberately, because nobody should put something in a
public channel under their own name without reading it. Above that is one line saying either
"Ready" or the single reason it will not send: no channel, wrong rank, in combat, nothing to
recruit, or *"Threnody barked 4m ago"*. Underneath is who has been recruiting recently.

**Teams** is one table, not one per team: a heading row per team with its needs underneath.
Each need has a role, a class (or blank for any), a count and a priority. Priority is what
decides what survives when the message will not fit.

A raid leader can add, edit, reorder and remove both teams and needs from here. The buttons
on a **team's heading row** are:

| Button | What it does |
| --- | --- |
| Edit | Opens the team's name, tag and raid days in the panel above the list |
| On / Off | Leaves the team out of the message without deleting it or its needs |
| ^ | Moves the team up. This is not cosmetic — the order decides which team leads the line |
| X | Removes the team and everything it was asking for. The last team cannot be removed |

The buttons on a **need row** are Edit, `^` to raise its priority, and X to remove it.

Three things about editing a team are worth knowing:

- **The tag is what actually goes in the message**, not the name — a 255-character line has
  no room for "Tuesday Core Raid Team". Keep it short.
- **Leave the tag blank and it builds itself** from the name's initials: "Molten Core"
  becomes "MC". That is also how you make a tag follow a rename, since a tag you have typed
  is never overwritten.
- **Adding a team opens the editor straight away.** A new team is called "Team 3" and has no
  raid days, which is not something you want going out to the guild.

Names and days are capped at 24 characters and tags at 8, because everything here has to
fit in one chat line alongside everything else.

**Message** is raid-leader only. `{teams}` is where the teams go; `{guild}` and `{contacts}`
fill themselves in. A second template says how one team is written, with `{tag}`, `{days}`
and `{needs}`. The preview under it re-assembles as you type, with a length meter.

**Officers** is the tab that answers *"why is Threnody sending the old line"*. Green has your
revision, amber is behind, blue is ahead of you.

**Log** is what the addon did and what it saw other officers do: sent, armed, skipped, others,
message.

**Settings** holds the rank thresholds, the channel, the pause rules and the buttons for
`/gr probe` and `/gr test`.

## How the message is assembled

Both teams go in **one line**, because two lines is two lines' worth of guild spam. A chat
message is 255 characters, so the addon gives up detail in named steps rather than cutting
the line off:

| | Looks like |
| --- | --- |
| everything | `T1 Tue/Thu 8-11: 2x Priest Healer, 3x DPS` |
| without classes | `T1 Tue/Thu 8-11: 2x Healer, 3x DPS` |
| without days | `T1: 2x Healer, 3x DPS` |
| without counts | `T1: Healer, DPS` |
| then it starts dropping needs | `T1: Healer` |

Needs are dropped lowest-priority first, and from whichever team currently has the most,
alternating — so **both team tags are in the message whenever they fit at all**. One team is
never quietly starved out of a combined line. Whatever did not fit is reported on the Bark
tab as *"2 needs left out"* rather than silently vanishing.

Which team leads rotates each time you send, so the same one is not always the one that
loses detail.

## Keeping in step

Every officer's copy carries a revision number. An edit stamps a revision above anything that
client has ever seen — including messages it looked at and decided against — so a revision is
about *causality*, not clocks.

When two raid leaders edit within the same minute, the tie is broken by the newer timestamp
and then, failing that, by the author's name. That last one is an arbitrary coin flip on
purpose: what matters is that every client flips it the same way, so nobody's copy oscillates.

At login your client sends one small "I hold revision N". Anyone whose copy is genuinely
newer answers after a random two to seven seconds and cancels if they hear a better answer
first — so in a guild that already agrees, eight officers logging in produce eight tiny
messages and not one full send.

When you bark, a short notice goes to the other officers so their gate can say *"you barked
90s ago"*. **The text itself is never sent between officers** — everyone is converging on the
same revision, so the number is enough. Barks sent while you were offline are not recovered,
and the panel says so rather than quietly showing you a short list.

## Commands

| Command | Effect |
| --- | --- |
| `/gr` | Open or close the window |
| `/gr send` | Send the recruitment message now |
| `/gr preview` | Print what would go out, and how long it is |
| `/gr on` / `off` | Turn the reminder timer on or off |
| `/gr every <mins>` | How often to remind you (5 minutes to an hour) |
| `/gr quiet <mins>` | How long to stay quiet after another officer barks; 0 turns it off |
| `/gr push` | Send your message to the other officers |
| `/gr sync` | Ask the guild for a newer one |
| `/gr who` | Which officers have which revision |
| `/gr rank author\|bark <n>` | Set the thresholds |
| `/gr log [n]` | Print the last n log lines |
| `/gr probe` | Report which client APIs this build has, then test the guild channel |
| `/gr status` | One line per part of the addon |
| `/gr test` | Run the test suite |
| `/gr enable` / `disable` | Master switch |
| `/gr out [n]` | Print to ChatFrame n |
| `/gr scale [percent]` | Window size, 50 to 125. You can also drag the grip in the window's bottom-right corner |
| `/gr reset [doc\|peers\|log\|all]` | Restore defaults |

Two key bindings under **GuildRecruitment**: send the message, and open the window.

## What the client will not let it do

**A timer cannot send.** `SendChatMessage` to a public channel is protected on this client:
it only goes through from a keypress or a click. So the timer *arms* — a sound and a chat
line — and a key binding, the Send button, the minimap right-click or `/gr send` does the
sending. There is no way around this and no addon has one.

**Nothing in this repo had ever sent an addon message or read the guild roster before this
addon**, so neither behaviour is in the client notes yet. `/gr probe` reports which functions
this build has and then sends a real message to the guild channel and waits to hear it back,
which is the only thing that proves the channel works. If it does not, the addon says so in
red at login and every officer's copy simply stays local — you can still write and send a
message, you just each keep your own.

`/gr probe noreg` turns prefix registration off and asks you to reload, which answers the
other open question: whether a prefix has to be registered before `CHAT_MSG_ADDON` fires at
all on this client.

## Safety

Everything arriving from another player is data, never markup and never code. Only messages
carried on the **guild** channel are considered at all, which removes every attack that does
not begin with already being in the guild. After that: the sender must be on your roster,
their rank is the one **your** client reads for them (a rank claimed inside a message is a
claim, not a permission), a message claiming somebody else wrote it is dropped, every string
is stripped of escapes and cut to a length this addon chose, and timestamps outside a sane
window are refused. `/gr status` counts what was ignored and why.

## Disclaimer

Automated advertising must comply with the game's Code of Conduct. Recruiting into a public
channel too often will annoy people whatever an addon says about it, which is why the timer
is off by default, the shortest reminder is five minutes, and the addon stays quiet for ten
minutes after another officer has already posted. Those numbers are yours to change, and so
is the responsibility.
