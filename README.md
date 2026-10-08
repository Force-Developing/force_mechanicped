# force_mechanicped

An NPC mechanic that repairs vehicles for a fee while no player mechanics are on duty. Drive onto the marker, confirm the price, step out and the mechanic walks over and repairs your vehicle under an ox_lib progress bar.

Free and open source. Works on ESX Legacy, QBCore and QBox.

## Features

- Server-side checks: mechanics on duty (configurable jobs), price from the config (cash, bank or both), the player drives the vehicle at the location, repair time, cooldown and a busy lock
- Refund when the repair is cancelled, rejected, times out, or the player or resource leaves mid-repair
- ox_target, qb-target or [E] with the ox_lib text UI
- Local mechanic ped with a map blip, several locations
- Vehicle is unfrozen and unlocked again on cancel, death and resource restarts
- English and Swedish locales

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- OneSync
- ESX Legacy, QBCore or QBox (other frameworks through `server/custom/frameworks/custom.lua`)
- Optional: ox_target or qb-target

No database is used.

## Installation

1. Put the folder in your resources as `force_mechanicped`.
2. Add `ensure force_mechanicped` to `server.cfg` below `ensure ox_lib`. The order relative to your framework and target resource doesn't matter.
3. Edit `config.lua`: price, account, mechanic jobs and locations.

## Documentation

https://docs.forcedevelopments.com/free-resources/force_mechanicped/introduction

## License

Apache 2.0, see [LICENSE](LICENSE).
