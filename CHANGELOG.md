# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
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
- Fix PostgreSQL on this machine (#82)
- Add database error handling and transactional persistence (#73)
- Fix Three.js memory leaks - building disposal, preview arrows, shared geometry/materials (#72)
- Wire production statistics into tick processor (#51)
- Fix resource rendering: remove hatched overlay, keep vertex-color glow (#20)

### Changed
- Add astral ingots to fabricator construction cost (#113)
- Move assembler to clearance 1, crossover to clearance 2 (#112)
- Replace common names with bureau names throughout user guide (#111)
- Update user guide with clumpy ore distribution info (#110)
- Replace ETS tab2list() with targeted queries (#74)
