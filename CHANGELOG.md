# Changelog — lxr-horses

## 3.0.0 — 2026-09-19
* The horse takes lxr-interact cards (feed, brush, pat, saddlebags, inspect — the native prompts only when lxr-interact is not running) and has its own doings: graze, drink at water, rest, rear — bond-gated, cooled down, each filling cores and earning bond with the game's own animal animations (`Config.Actions`).
* Hand-over: offer one of your horses to the closest player for a price or as a gift (`/horsetrade` or the card); accepted face to face, ownership, tack and saddlebags move with it (`Config.Trade`, event `lxr:horse:traded`).
* Fix: `LXRCore.PlayerData` stays current — the core object comes back as a copy, so cash, job and metadata never changed after login in this resource. It now listens to `lxr:client:data` / `lxr:client:unloaded` and refreshes its copy.
* Stables and training courses are lxr-interact cards instead of native prompts.
* LXRCore v3 release line: every resource ships as 3.0.0 from here (the entries below are the road to it).

## [1.0.0] — 2026-09-17
### Added
- Ownership, stables NUI, cores & bonding, personalities, tack catalog (546 pieces), saddlebags, wild herds & taming, training courses, player market, transfer, insurance, breeding, overhead tag, admin command, exports.
- Offline tests for the logic module; locales en/ka; 1899 prices and fees.
