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

## Not verified yet

Everything above was paid for. These are the opposite: things the code guards against
because nobody has ever run them on this client. Replace an entry with what actually
happened the first time somebody does.

**Addon messages.** Whether `C_ChatInfo.SendAddonMessage` exists on 20506 or only the bare
`SendAddonMessage`; whether `RegisterAddonMessagePrefix` is required before
`CHAT_MSG_ADDON` fires at all; whether the 255-byte cap counts the prefix; whether your own
`GUILD` message is echoed back to you. `GuildRecruitment` tries both names, guards every
call in `pcall`, and `/gr probe` reports which answered and then sends a real message and
waits for it — the round trip is the only thing that proves the channel carries anything.
`/gr probe noreg` plus a `/reload` answers the registration question on its own.

**The guild roster.** The exact return positions of `GetGuildRosterInfo(i)` on 20506, and
whether `rankIndex` is 0-based with 0 meaning guild master. Everything that decides
permission takes the index as an argument and is pure, so if the polarity turns out to be
inverted only `Roster.Read` changes.

**`SendChatMessage` to `GUILD`.** The hardware-event rule above is documented for `CHANNEL`
and `SAY`. Nothing has tried `GUILD`. Assume it needs one until somebody finds out.
