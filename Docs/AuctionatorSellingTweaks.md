# Auctionator Selling Tweaks

A small companion for Auctionator on TBC Anniversary. It does two things to the Selling
tab:

- **Guards against posting far under the market.** Before an item goes up, the price is
  checked against the cheapest listing on the auction house right now (or, with none,
  Auctionator's last known price for the item). More than 40% under it, and Auctionator's
  own confirm dialog opens with the numbers: what you typed, what the market is, how far
  under you are. Accept posts, Cancel does not, and Skip moves to the next item when you
  are posting a run of them.
- **Adds an Expiry column** just before **You?** in the price list shown while posting,
  visible by default, and narrows **You?** to the space the tick needs.

Nothing inside Auctionator's own files is edited. Both changes wrap a function Auctionator
already calls, so Auctionator updates keep working; if a future version moves one of them,
the addon leaves that part alone and says so at login.

## Why the guard

Auctionator has its own "unusually low price" check, but it only looks at stackable items,
compares against the fifth listing rather than the first, and can be switched off. A piece
of gear posted at a tenth of the going rate sails through it. This one applies to every
item, measures against the cheapest listing, and runs whether or not Auctionator's own
check is on. The two do not fight: when both would speak, this one does.

## Install

Extract into `_anniversary_\Interface\AddOns` so you get
`AddOns\AuctionatorSellingTweaks\AuctionatorSellingTweaks.toc`. It requires Auctionator and
ICLibs, and does nothing without them. Reload after installing.

## Commands

```
/ast                    what the guard is set to
/ast floor <percent>    how far under the market a price must be before it asks (default 40, 1 to 90)
/ast guard on|off       the posting guard
/ast columns on|off     the Expiry column; takes effect after a reload
/ast test               run the built-in checks
```

## About the times shown

The legacy auction house on this client only reports time left in four bands, so Expiry
shows one of: Short (under 30 minutes), Medium (30 minutes to 2 hours), Long (2 to 12
hours), Very Long (12 to 48 hours). Exact minutes are not available from the game.

## If you want the old layout back

`/ast columns off` and reload. Auctionator's own "Time Left" column can still be switched
on by right-clicking the column headers in that list.
