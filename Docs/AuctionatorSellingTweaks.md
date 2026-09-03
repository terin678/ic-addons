# Auctionator Selling Tweaks

A one-file companion for Auctionator on TBC Anniversary. It changes the column layout of
the price list on Auctionator's Selling tab, the list of current auctions shown while you
post an item:

- Adds an **Expiry** column just before **You?**, visible by default. It shows the auction's
  remaining time band.
- Narrows **You?** so it takes only the space the tick needs.

Nothing inside Auctionator's own files is edited. The addon wraps the function Auctionator
uses to describe those columns, so Auctionator updates keep working; if a future version
renames the columns, the addon leaves the layout alone and prints a note at login.

## Install

Extract into `_anniversary_\Interface\AddOns` so you get
`AddOns\AuctionatorSellingTweaks\AuctionatorSellingTweaks.toc`. It requires Auctionator and
does nothing without it. Reload after installing.

## About the times shown

The legacy auction house on this client only reports time left in four bands, so Expiry
shows one of: Short (under 30 minutes), Medium (30 minutes to 2 hours), Long (2 to 12
hours), Very Long (12 to 48 hours). Exact minutes are not available from the game.

## If you want the old layout back

Disable the addon. Auctionator's own "Time Left" column can still be switched on by
right-clicking the column headers in that list.
