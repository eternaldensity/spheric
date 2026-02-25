# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Add cost for loader/unloader stack_upgrade (#163)
- Implement resonance cascade world event effect (#162)
- Implement area creature boost for 5 buildings (#161)
- Implement efficiency creature boost: skip input consumption (#160)
- Wire 3 unimplemented altered item effects: purified_smelting, trap_radius, teleport_output (#159)
- Implement all 6 missing Objects of Power effects (L2-L4, L6-L8) (#158)
- Add delivery drone and delivery cargo upgrades to user guide (#157)
- Per-tier conduit movement speed (#153)
- Reduce drone fuel consumption when idle and near ground (#125)
- Hide drone bay upgrades until construction complete (#122)
- Clumpy ore distribution: cluster resource deposits into veins (#109)
- Add Scoop and PostgreSQL installation instructions to server guide (#83)
- Add Windows PostgreSQL Error 1067 troubleshooting to server guide (#81)
- Expand server guide troubleshooting with database and common failure recovery (#80)
- Add server setup and operation guide page (#79)
- Bulk demolish mode for area removal of structures (#60)
- Phase 7: Advanced Logistics & Polish (#49)
- Add blueprint tool for stamp-placing building patterns (#52)
- Add deep production chains: Assembler activation, Refinery, 4 new resources, multi-tier recipes (#40)

### Fixed
- Add whispering_powder and whispering_ingot to item renderer (#164)
- Fix move_ticks KeyError in advance_conveyor_cooldowns (#155)
- Storage vault: separate stored vs inserted items for arm transfer fairness (#154)
- Add DB fallback when Research ETS cache misses player unlocks (#130)
- Fix assembler building not creating construction site (#129)
- Fix drone bay mode not atomized after persistence load (#123)
- Fix stuck world events after server reload (#121)
- Fix PostgreSQL on this machine (#82)
- Add database error handling and transactional persistence (#73)
- Fix Three.js memory leaks - building disposal, preview arrows, shared geometry/materials (#72)
- Wire production statistics into tick processor (#51)
- Fix resource rendering: remove hatched overlay, keep vertex-color glow (#20)

### Changed
- Update guide and scripts for whispering items and arm upgrade costs (#165)
- Add astral ingots to fabricator construction cost (#113)
- Move assembler to clearance 1, crossover to clearance 2 (#112)
- Replace common names with bureau names throughout user guide (#111)
- Update user guide with clumpy ore distribution info (#110)
- Replace ETS tab2list() with targeted queries (#74)
