# Auto Train Adder

Automatically deploy trains based on circuit network signals in Factorio 2.0.

Place a **Train Deployer** on rails, save a train as a template, and let circuit signals control your fleet. A **Train Monitor** reports fleet counts and utilization back to the circuit network.

## Features

### Train Deployer
- Place on rails like a regular train stop
- Park a train at the stop and save it as a reusable template (layout, schedule, fuel)
- Up to 8 templates, each mapped to a circuit signal (`ata-template-1` through `ata-template-8`)
- When a positive signal is detected, deploys one train per cycle (~30 seconds by default)
- Consumes locomotive, wagon, and fuel items from an internal inventory
- Inserters can load items into the deployer
- Sends Factorio alerts when items are missing
- Outputs chest contents on the circuit network for automated resupply

### Train Monitor
- Place anywhere (no rail connection needed)
- Auto-discovers all train types by layout (e.g., `L-C`, `L-C-C-C`, `L-F`)
- Outputs train counts on `signal-0` through `signal-9`
- Outputs utilization percentage on `signal-A` through `signal-J`
- Utilization = trains actively working / total trains of that type
- Trains at depot stations count as idle (configurable depot name pattern)

### Templates
- Save any train composition: locomotives, cargo wagons, fluid wagons, artillery wagons
- Preserves schedule, orientation, and fuel configuration
- Supports modded rolling stock (e.g., Py mods `mk02-locomotive`)

## How to Use

### 1. Research the Technology
Research **Automatic Train Deployment** (requires Automated Rail Transportation + Circuit Network).

### 2. Set Up a Train Deployer
1. Craft a Train Deployer and place it on rails (snaps like a train stop)
2. Load it with locomotives, wagons, and fuel using inserters or manually
3. Drive or schedule a template train to the deployer stop
4. Click the deployer, name your template, pick a signal slot (1-8), and click **Save Template**

### 3. Wire Circuit Signals
1. Connect a circuit wire (red or green) to the deployer
2. Send a positive value on the corresponding `ata-template-N` signal (look for the locomotive icon with a number badge)
3. Every ~30 seconds, the deployer checks for positive signals and deploys one matching train

### 4. Monitor Your Fleet
1. Craft a Train Monitor and place it anywhere
2. Connect circuit wires to read the output
3. The monitor auto-assigns signals based on train types sorted alphabetically:
   - First type found gets `signal-0` (count) and `signal-A` (utilization %)
   - Second type gets `signal-1` / `signal-B`, and so on
   - Up to 10 types supported

## Signal Reference

### Deployer Input Signals
| Signal | Description |
|--------|-------------|
| `ata-template-1` .. `ata-template-8` | Positive value triggers deployment of one matching template train |

### Deployer Output Signals
| Signal | Description |
|--------|-------------|
| `ata-status` | 0 = Idle, 1 = Building, 2 = Error |
| Item signals | Current chest contents (for resupply automation) |

### Monitor Output Signals
| Signal | Description |
|--------|-------------|
| `signal-0` .. `signal-9` | Train count per type (sorted alphabetically by layout) |
| `signal-A` .. `signal-J` | Utilization % per type (paired with count signals) |

## Mod Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Deployer update rate | 1800 ticks (30s) | How often the deployer checks for deploy signals |
| Monitor update rate | 60 ticks (1s) | How often the monitor refreshes train counts |
| Depot station pattern | `depot,D` | Comma-separated patterns. Trains at matching stations count as idle |
| Debug logging | Off | Enable file logging to `script-output/auto-train-adder.log` |

## Compatibility

- **Factorio 2.0 / Space Age** required
- Works with modded rolling stock (Py mods, etc.)
- Compatible with other train management mods

## License

MIT License - see [LICENSE](LICENSE) for details.
