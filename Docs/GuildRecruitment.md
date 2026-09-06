# Guild Recruitment

One recruitment message the raid leaders set and every officer sends, kept in step across
the guild, with a log of who barked when.

The problem it solves: every raid officer recruiting, everyone typing their own line into a
channel. Nobody knows who posted last, so two officers post four minutes apart, and the
wording drifts until the guild is advertised differently by different people.

The message is one line of plain text, at most 255 characters, sent exactly as a raid
leader wrote it. There are no teams to set up, no templates and no tokens: the line usually
ends in "/w me", and that is the whole of it.

## Install

```powershell
.\scripts\deploy.ps1 -Flavor anniversary -Addon GuildRecruitment
```

That links ICLibs alongside it, because GuildRecruitment lists it under `## Dependencies`.
Then `/reload`, and `/gr` opens the window.

## Quick start

1. A raid leader opens the **Message** tab, writes the line, and presses **Save and push**.
   Every officer who is online and running the addon takes it within a few seconds.
2. Any officer opens **Bark**, reads the line, and presses **Send now**.

Barking is off by default. Turning the reminder on means a sound and a chat line when it is
time; it does not send anything by itself, and it cannot (see below).

**Updating from 0.3.** The message starts empty: the teams, needs and templates of the old
model cannot be turned into a line, so a raid leader types the new one once. Old and new
clients do not read each other's messages at all, so update everyone together.

## Who may do what

Authority is a guild rank threshold, and `rankIndex 0` is the guild master — a **larger**
number is a **lower** rank, so both settings are ceilings.

| Setting | Default | Means |
| --- | --- | --- |
| Raid leaders | rank 2 or better | may change the message and push it |
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
"Ready" or the single reason it will not send: no channel, wrong rank, in combat, no message
set yet, or *"Threnody barked 4m ago"*. Underneath is who has been recruiting recently.

**Message** is raid-leader only: one box, and the line in it is what the whole guild sends.
Pipes and line breaks come out and runs of spaces close up, because a chat channel refuses
the first and the second would make two clients disagree about a line that reads the same;
nothing else is changed. The meter under the box counts characters against the 255 a chat
message takes, and while the box differs from the saved message it says **unsaved**.
Nothing reaches anyone until **Save and push**; **Revert** puts the box back. Typing here
does not move the revision every other officer is watching, which is why the two are kept
apart.

**Officers** is the tab that answers *"why is Threnody sending the old line"*. Green has your
revision, amber is behind, blue is ahead of you.

**Log** is what the addon did and what it saw other officers do: sent, armed, skipped, others,
message.

**Settings** holds the rank thresholds, the channel, the pause rules and the buttons for
`/gr probe` and `/gr test`.

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

A push carries the line itself, so a new officer has the exact text within seconds of
logging in. When you bark, only a short notice goes to the other officers — who, when, which
channel, which revision — so their gate can say *"you barked 90s ago"*. Barks sent while you
were offline are not recovered, and the panel says so rather than quietly showing you a
short list.

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
| `/gr reset [doc\|peers\|log\|all]` | Restore defaults; `doc` empties the message without telling anyone |
| `/gr version` | Addon and library versions |

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
