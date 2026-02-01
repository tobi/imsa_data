# Claude Code Project Notes

## Architecture Principles

### Metadata in JSON, Not SQL

**Problem**: The SQL files have accumulated hardcoded patterns for event naming, session normalization, and multi-event detection. This is fragile and hard to maintain.

**Current hardcoded patterns in SQL**:
- `6h---` prefix detection for 6-hour events
- `weathertech-240---` prefix for WeatherTech 240 races
- `roar-before-the-24` ROAR event detection
- `-6-hours` / `-8-hours` suffix for WEC multi-event weekends
- `race-201-hour`, `race-202-hour` patterns for ALMS multi-race weekends
- Session type normalization (practice, qualifying, race, warmup, test)

**Better approach**: Create a JSON metadata file for event configuration:

```json
{
  "event_patterns": [
    {
      "pattern": "^([0-9]+)h---",
      "suffix": " $1 Hours",
      "description": "Duration prefix events (e.g., 6h---watkins-glen)"
    },
    {
      "pattern": "roar-before",
      "suffix": " ROAR",
      "description": "ROAR Before the 24 test event"
    },
    {
      "pattern": "-([0-9]+)-hours?$",
      "suffix": " $1 Hours",
      "description": "WEC duration suffix events (e.g., bahrain-6-hours)"
    }
  ],
  "multi_race_patterns": [
    {
      "session_pattern": "^race-20([0-9])-hour",
      "event_suffix": " Race $1",
      "description": "ALMS-style multi-race weekends"
    }
  ],
  "session_normalization": {
    "race": ["race%"],
    "qualifying": ["qualifying%", "hyperpole%", "r24h-qualifying%"],
    "practice": ["free%practice%", "practice%", "night%session%", "morning%session%", "afternoon%session%"],
    "warmup": ["warm%up%"],
    "test": ["%test%", "session-%", "lmp2%session", "lmgt3%session"]
  }
}
```

### SQL Should Be Generic

SQL files should:
1. Load patterns from JSON metadata files
2. Apply patterns using macros/functions
3. Not contain hardcoded event names, patterns, or special cases

### Existing JSON Metadata Files

- `tracks.json` - Track aliases and coordinates
- `chassis.json` - Chassis homologation mappings
- `classes.json` - Main class definitions by series

### TODO: Refactor Event Naming

1. Create `events_config.json` with event patterns
2. Create SQL macros to read and apply patterns
3. Remove hardcoded CASE statements from SQL files
4. Test thoroughly with existing data

## Current Data Pipeline

1. `import.rb` - Downloads raw CSV files from Al Kamel Systems
2. `000-settings.sql` - Creates tracks, classes, macros
3. `010-event-drivers.sql` - Processes results CSVs for driver data
4. `011-chassis.sql` - Processes results CSVs for chassis data
5. `020-event-laps.sql` - Processes laps CSVs (main lap data)
6. `030-event-weather.sql` - Processes weather CSVs
7. `071-events.sql` - Creates events table
8. `080-event-metadata.sql` - Adds race duration, famous names, etc.

## Known Issues

### Multi-Event Weekends Not Fully Working

Some events at the same track on different weekends are not being split correctly:
- IMSA 2022 Daytona: "ROAR Before the 24" test event merging with main 24H race
- The LIKE pattern for "roar-before" exists but isn't being applied correctly

### Missing Race Data for Some Events

Several ALMS events show practice/qualifying but no race data - this is an upstream data limitation.

## Series Supported

- IMSA (imsa)
- WEC (wec)
- ELMS (elms)
- ALMS - Asian Le Mans Series (alms)
- LMC - Le Mans Cup (lmc)
