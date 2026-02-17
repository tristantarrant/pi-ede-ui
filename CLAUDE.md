# Pi-EDE UI

Flutter-based HMI (Human-Machine Interface) for MOD Audio's mod-ui system, designed for Raspberry Pi.

## Project Structure

```
lib/
├── main.dart           # App entry point, navigation, drawer
├── hmi_server.dart     # TCP HMI server (mod-ui connects as client)
├── hmi_protocol.dart   # Protocol constants mirroring mod-ui's mod_protocol.py
├── pedalboards.dart    # Pedalboard list/switcher widget
├── pedalboard.dart     # Pedalboard model (parses TTL files)
├── pedal.dart          # Pedal/plugin model, LV2PluginCache
├── pedal_editor.dart   # Parameter editor for pedals
├── bank.dart           # Bank model (loads from banks.json)
├── banks.dart          # Bank selection widget
├── tuner.dart          # Chromatic tuner widget
├── snapshots.dart      # Snapshot management widget
├── transport.dart      # Tempo/transport control widget
├── bypass.dart         # Quick bypass and channel bypass widget
├── midi_settings.dart  # MIDI clock source/send settings widget
├── profiles.dart       # User profiles widget
├── qr.dart             # Wi-Fi QR code widget
└── gpio_client.dart    # GPIO client for hardware buttons
```

## Architecture

### HMI Protocol
- Bidirectional TCP communication on port 9898
- Flutter app runs as **server**, mod-ui connects as **client**
- Commands are null-terminated strings (e.g., `pb 1 2\x00`)
- Protocol constants in `hmi_protocol.dart` mirror `mod-ui/mod/mod_protocol.py`

### Custom Protocol Extensions
- `cps` (CMD_CONTROL_PARAM_SET): Set plugin parameter values directly
  - Format: `cps <instance> <port_symbol> <value>`
  - Added to mod-ui in `mod/mod_protocol.py` and `mod/host.py`

### Data Paths
- `MOD_DATA_DIR` environment variable (fallback: `$HOME/data`)
- Pedalboards: `$MOD_DATA_DIR/pedalboards/`
- Banks: `$MOD_DATA_DIR/banks.json`
- LV2 plugins: `/usr/lib/lv2/`, `~/.lv2/`

## Key Classes

### HMIServer (hmi_server.dart)
Event streams:
- `onPedalboardChange` - pedalboard switch events
- `onPedalboardLoad` - pedalboard load events
- `onTuner` - tuner frequency/note/cents data
- `onSnapshots` - snapshot list updates
- `onMenuItem` - menu item value changes (tempo, bypass, MIDI settings)
- `onProfiles` - profile list updates

Outgoing commands:
- `loadPedalboard(index, {bankId})` - load pedalboard
- `setParameter(instance, portSymbol, value)` - set plugin parameter
- `savePedalboard()` - save current pedalboard
- `tunerOn/Off()`, `setTunerInput()`, `setTunerRefFreq()`
- `loadSnapshot()`, `saveSnapshot()`, `saveSnapshotAs()`, `deleteSnapshot()`
- `setTempo()`, `setBeatsPerBar()`, `setPlayStatus()`
- `setQuickBypass()`, `setBypass1()`, `setBypass2()`
- `setMidiClockSource()`, `setMidiClockSend()`
- `loadProfile()`, `storeProfile()`

### LV2PluginCache (pedal.dart)
- Singleton that scans LV2 plugin directories
- Parses `manifest.ttl` and `modgui.ttl` for plugin metadata
- Caches `LV2PluginInfo` with control ports, thumbnails, etc.

### Pedalboard (pedalboard.dart)
- Parses pedalboard TTL files using rdflib
- `getPedals()` extracts plugin instances with current parameter values
- Sorting by path matches mod-ui's Lilv enumeration order

## Widget Index (drawer order)

| Index | Widget | Icon | Description |
|-------|--------|------|-------------|
| 0 | PedalboardsWidget | music_note | Pedalboard list/switcher |
| 1 | BanksWidget | folder | Bank selection |
| 2 | qrWidget | wifi | Wi-Fi QR code |
| 3 | TunerWidget | tune | Chromatic tuner |
| 4 | SnapshotsWidget | camera | Snapshot management |
| 5 | TransportWidget | speed | Tempo/transport control |
| 6 | BypassWidget | volume_off | Quick/channel bypass |
| 7 | MIDISettingsWidget | piano | MIDI clock settings |
| 8 | ProfilesWidget | person | User profiles |

## Dependencies

Key packages:
- `rdflib` - RDF/Turtle parsing for pedalboard/plugin TTL files
- `dart_periphery` - GPIO access for hardware buttons
- `ffi` - FFI for system calls (shutdown)
- `network_info_plus` - Network info for QR widget
- `qr_flutter` - QR code generation

## Related Project

mod-ui repository at `../mod-ui`:
- `mod/mod_protocol.py` - HMI protocol definitions
- `mod/host.py` - HMI command handlers
- Custom `cps` command added for parameter setting

## Build & Run

```bash
flutter pub get
flutter run -d linux  # For desktop testing
flutter build linux   # For deployment
```

## Notes

- Pedalboards sorted by path to match Lilv enumeration order
- Parameter changes via `cps` are volatile (mark pedalboard modified but don't auto-save)
- Tuner auto-disables on widget dispose
- Some HMI features are firmware-level only (noise gate, compressor, system info)
