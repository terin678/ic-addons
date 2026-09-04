# Client API contracts that have already cost us

Every entry here is something that shipped broken, was found in game or in review, and is
not obvious from the code. The symptom is written down first, because the symptom is what
you will have in front of you.

Client: TBC Anniversary, interface 20506. Retail documentation is often wrong for it.

## Drawing

**Every frame draws with no fill at all, text and icons still visible.** The backdrop's
`bgFile` does not resolve. `Interface\Buttons\WHITE8x8` (capitals) exists on this client;
`Interface\Buildings\White8x8` does not. A missing texture is silent: no error, no
placeholder, just nothing.

**A scrollbar lands outside the window, or over the next table.**
`UIPanelScrollFrameTemplate` draws its scrollbar just beyond the scroll frame's own width.
The frame must be exactly as wide as its rows, and the caller leaves 26px to its right.

**A frame reports `GetWidth()` of 0.** A frame anchored on two sides has no size until the
first layout pass. Anything computing geometry at build time needs a fallback width.

**A FontString ignores `SetScript`.** FontStrings are regions, not frames: no scripts, no
mouse. A hover or clickable cell needs an invisible Button on top of it (`col.hit` in
LibICUI's `Table` does this).

**`Button:SetText` does nothing.** A bare Button has no font string until
`SetFontString(fs)` is called. LibICUI's `Button` does it; a hand-rolled one must too.

**A rotated texture comes out unrotated.** `Texture:SetRotation` turns the picture
*inside* a rectangle that does not move, so a `SetColorTexture` fill looks identical at
every angle. There is no polyline primitive either. To draw a sloped line you need artwork
that is already sloped plus the 8-argument `SetTexCoord`; to draw a chart line without art,
use steps — a flat run per slot and an upright joining one run to the next, all
axis-aligned. MAW's `Chart.lua` does the latter.

## Items and links

**A guard that reads an item's class silently fails for a stranger's link.**
`GetItemInfo(id)` returns *nothing at all* for an item this client has never cached, so
`select(12, GetItemInfo(id))` is nil and every test on it is false. That is exactly the
case a link from a stranger falls into. Never let "we could not identify it" mean "it is
not interesting".

**A linked recipe has no item id.** Shift-clicking a recipe out of a profession window
posts `|Htrade:3811:1:300:2:0|h[Leatherworking: Bindings of Lightning Reflexes]|h`. There
is no `|Hitem:` in it. Link types seen in chat: `|Hitem:` items, `|Htrade:` recipes,
`|Henchant:` enchants, `|Hspell:` spells, `|Hquest:` quests. The one thing they share is
`[Display Name]` in brackets, which is why `Util.BracketNames` reads brackets rather than
hunting for a particular link type.

**`GetCoinTextureString` errors on anything but a whole positive number.** It refuses
negatives (a correction), and money is fractional whenever it came from a division. Round
and take the absolute value before calling it, and put the sign back yourself.

## The profession window

**A recipe is missing from the list even though the player knows it.**
`GetNumTradeSkills()` counts only the children of *expanded* headers. A recipe under a
collapsed category is absent, not filtered. `ExpandTradeSkillSubClass(0)` opens them all.

**Return positions**: `GetTradeSkillInfo(i)` is
`skillName, skillType, numAvailable, isExpanded, altVerb, numSkillUps`. `skillType` is
`"header"` for a category row. `GetTradeSkillItemLink(i)` is the product's link,
`GetTradeSkillNumMade(i)` is `minMade, maxMade`.

**Selecting a recipe does not scroll to it.** `TradeSkillFrame_SetSelection(i)` updates the
detail pane and leaves the list where it was. The list is a faux scroll frame: set
`FauxScrollFrame_SetOffset` *and* the scrollbar's value, which is what redraws it.

**The create count box** is the global `TradeSkillInputBox`. Confirmed present on 20506:
`/run print(TradeSkillInputBox, TradeSkillInputBox:GetNumber())` answers with the frame and
the number between the arrows. Do not overwrite it while it has focus; the player may be
typing in it.

**Two different links, and only one lists reagents.** `GetTradeSkillItemLink(i)` is the
*product* (`|Hitem:`). `GetTradeSkillRecipeLink(i)` is the *craft* (`|Htrade:`), and that is
the one whose tooltip lists the reagents — which is what makes it worth handing to a
customer. Nothing here called it before TradeMaster 1.9.0, so treat nil as expected and
guard it; `/tm probe` reports whether this client has it.

## Secure frames and combat

**Attributes cannot be touched in combat.** `SetAttribute` and `RegisterForClicks` on a
secure button are blocked once `InCombatLockdown()` is true. A pooled row therefore keeps
the *previous* item's attributes: disable the button rather than leave it pointing at
someone else's action. Creating frames in combat is fine; only the secure calls are not.

## Chat

**A public channel message needs a hardware event.** `SendChatMessage` to `CHANNEL` or `SAY`
only works from a keypress or click, which is why barking arms a state and a button sends
it. Whispers have no such restriction.

## Saved variables

**Data that "disappeared" on reload was usually never saved.** A field on a Lua table that
is not inside the saved-variables table is session state, and a filter or toggle kept there
looks exactly like data loss the next time the player logs in. If it changes what the
player sees, it belongs in the saved table.

**A channel list has a stride of three.** `GetChannelList()` returns a flat
`id, name, disabled, id, name, disabled, ...`. Walking it two at a time reads every other
channel's name as an id, and the bug is invisible until the character has joined an odd
number of channels. `TradeMaster/Barker.lua` and `GuildRecruitment/Bark.lua` both step by 3.

## Addon messages and the guild roster

Answered by `/gr probe` on 20506, so these are facts now rather than guesses.

**`C_ChatInfo` is the live path; the bare globals are gone.**
`C_ChatInfo.SendAddonMessage` and `C_ChatInfo.RegisterAddonMessagePrefix` both exist;
`SendAddonMessage` and `RegisterAddonMessagePrefix` as globals do **not**. Registration is
accepted. Resolve the namespaced name first and keep the global only as a fallback for
other flavours.

**`GuildRoster()` does not exist either**, under that name. `IsInGuild`,
`GetNumGuildMembers`, `GetGuildRosterInfo` and `GetGuildInfo` all do, and the roster is
populated without anyone asking for it -- a probe that never called a refresh still read
450 rows. `GuildRecruitment/Roster.lua` tries `C_GuildInfo.GuildRoster` and falls back to
reading whatever is already there, because a refresh you cannot request is not a reason to
have no roster.

**A GUILD addon message comes back to the sender.** `/gr probe`'s loopback reported
"heard from Malexis in 0.00s" -- your own message is delivered to your own
`CHAT_MSG_ADDON` immediately. Useful, because it is what makes a loopback test possible at
all, but anything that walks the receive path has to drop its own traffic early or it files
itself as a peer, counts its own echo as received, and logs itself agreeing with itself.
`GuildRecruitment/Comm.lua` returns as soon as the loopback has been told.

**`GetGuildRosterInfo` returns a 0-based rankIndex** with 0 as the guild master, as
assumed: a rank-2 officer reads as 2.

**`loadstring` exists.** ICTemplate's gallery compiles each demo from the same string it
displays, and that rests on it.

## Lua, not the client

**luaparser does not catch an unfinished string.** A raw newline inside `"..."` is a load
error in the client -- "unfinished string near" -- and `luaparser` parses it happily, so
`scripts/lint.py`'s parse check called the file clean and it shipped. There is now a
`check_unfinished_strings` in lint.py that walks the source properly, skipping long strings
and comments. The lesson generalises: the parse check is a floor, not a ceiling.

**A table constructor cannot carry a nil.** `{ channel = nil }` is an *empty* table, so a
test helper that merges an overrides table silently applies no override and the field keeps
its default. This passed a Python port of the same cases -- a dict really can hold a `None`
-- and failed the first time it ran in the client. Clear the field on the built table
instead: `local s = state(); s.channel = nil`.
