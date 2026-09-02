# Retail addons

Target interface: see `Docs/client-reference.md`. Nothing here yet.

Note for anyone porting the auction watcher: retail uses the `C_AuctionHouse` API, not the
legacy `QueryAuctionItems` family, so `Scanning.lua` would need a new backend.
