# HUGINN - WiFi + BLE Identity Correlator
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

**Version 2.0.7** | *Named after Odin's raven - "thought" - sees all, correlates identities*

```
                              .......::.:....
                        ..::------------------::..
                      .:-=======================-::.
                    .:---====================-----::.
                  .:::::::-----=-----=--=---:::::::...
                ....:::::----====-=--====--------:::...
                ...::------::---=========--::::::--::.
                ....:::........:.:::::::..........:::.
                 .....      ........::..      ...   ..
                 . .            ..::....       ...
                              ...::.   ...
                   ..         .::.      ...          .
                  .:..     ......        .....      ....
               ... .:...........      .    .   .....::.
               ........  ..   ...       .....  ..........
                             .....      .....   ...
                              ...... .......
                           ...::.........:::.
                          ....... ....:......
                          ....     .  ....

 ██░ ██  █    ██   ▄████  ██▓ ███▄    █  ███▄    █
▓██░ ██▒ ██  ▓██▒ ██▒ ▀█▒▓██▒ ██ ▀█   █  ██ ▀█   █
▒██▀▀██░▓██  ▒██░▒██░▄▄▄░▒██▒▓██  ▀█ ██▒▓██  ▀█ ██▒
░▓█ ░██ ▓▓█  ░██░░▓█  ██▓░██░▓██▒  ▐▌██▒▓██▒  ▐▌██▒
░▓█▒░██▓▒▒█████▓ ░▒▓███▀▒░██░▒██░   ▓██░▒██░   ▓██░
 ▒ ░░▒░▒░▒▓▒ ▒ ▒  ░▒   ▒ ░▓  ░ ▒░   ▒ ▒ ░ ▒░   ▒ ▒
 ▒ ░▒░ ░░░▒░ ░ ░   ░   ░  ▒ ░░ ░░   ░ ▒░░ ░░   ░ ▒░
 ░  ░░ ░ ░░░ ░ ░ ░ ░   ░  ▒ ░   ░   ░ ░    ░   ░ ░
 ░  ░  ░   ░           ░  ░           ░          ░

                        HUGINN
                  ODIN'S RAVEN SEES ALL
```

## Overview

HUGINN defeats MAC address randomization by correlating WiFi and Bluetooth signals. Modern devices randomize their WiFi MAC addresses for privacy, but HUGINN correlates multiple signal types to track the **actual device** rather than just the MAC.

## The Problem: MAC Randomization

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                    MAC RANDOMIZATION                            │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │    Target's iPhone                                              │
    │    ┌─────────────┐                                              │
    │    │             │                                              │
    │    │   📱        │──────▶  WiFi MAC changes every few minutes   │
    │    │             │                                              │
    │    └─────────────┘                                              │
    │                                                                 │
    │    Time 0:00    ──▶   AA:BB:CC:11:22:33  (random)               │
    │    Time 0:05    ──▶   DD:EE:FF:44:55:66  (random)               │
    │    Time 0:10    ──▶   12:34:56:78:9A:BC  (random)               │
    │    Time 0:15    ──▶   FE:DC:BA:98:76:54  (random)               │
    │                                                                 │
    │    Traditional tracking: IMPOSSIBLE                             │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## The Solution: Multi-Signal Correlation

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                   HUGINN CORRELATION                            │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │    Target's iPhone                                              │
    │    ┌─────────────┐                                              │
    │    │             │                                              │
    │    │   📱        │──┬──▶  WiFi: Random MAC + Probe SSIDs        │
    │    │             │  │                                           │
    │    └─────────────┘  └──▶  BLE:  "John's iPhone" + Apple OUI     │
    │                                                                 │
    │                     ┌─────────────────────┐                     │
    │                     │  CORRELATION ENGINE │                     │
    │                     └──────────┬──────────┘                     │
    │                                │                                │
    │                                ▼                                │
    │    ┌───────────────────────────────────────────────────────┐   │
    │    │  MATCH FOUND:                                          │   │
    │    │  ├── WiFi Vendor: Apple                                │   │
    │    │  ├── BLE Vendor:  Apple                                │   │
    │    │  ├── BLE Name:    "John's iPhone"                      │   │
    │    │  └── Confidence:  HIGH                                 │   │
    │    │                                                        │   │
    │    │  >> Same device tracked despite MAC randomization <<   │   │
    │    └───────────────────────────────────────────────────────┘   │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## How It Works

```
                        ┌─────────────────────────────────────┐
                        │           HUGINN WORKFLOW           │
                        └─────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────────┐
    │                                                                  │
    │   STEP 1: DUAL-RADIO CAPTURE                                     │
    │   ════════════════════════════                                   │
    │                                                                  │
    │   ┌─────────────┐                         ┌─────────────┐        │
    │   │   wlan1mon  │                         │    hci0     │        │
    │   │  (Monitor)  │                         │   (BLE)     │        │
    │   └──────┬──────┘                         └──────┬──────┘        │
    │          │                                       │               │
    │          ▼                                       ▼               │
    │   ┌─────────────┐                         ┌─────────────┐        │
    │   │  tcpdump    │                         │  hcitool    │        │
    │   │  Probe Req  │                         │  lescan     │        │
    │   └──────┬──────┘                         └──────┬──────┘        │
    │          │                                       │               │
    │          ▼                                       ▼               │
    │   ┌─────────────────┐                   ┌─────────────────┐      │
    │   │ WiFi Probes     │                   │ BLE Devices     │      │
    │   ├─────────────────┤                   ├─────────────────┤      │
    │   │ MAC Address     │                   │ MAC Address     │      │
    │   │ SSID Looking For│                   │ Device Name     │      │
    │   │ Signal Strength │                   │ Signal Strength │      │
    │   │ Vendor (OUI)    │                   │ Vendor (OUI)    │      │
    │   └────────┬────────┘                   └────────┬────────┘      │
    │            │                                     │               │
    │            └──────────────┬───────────────────────┘               │
    │                           │                                      │
    │                           ▼                                      │
    │   STEP 2: CORRELATION                                            │
    │   ═══════════════════                                            │
    │                                                                  │
    │   ┌─────────────────────────────────────────────────────────┐   │
    │   │              CORRELATION ENGINE                          │   │
    │   ├─────────────────────────────────────────────────────────┤   │
    │   │                                                          │   │
    │   │   Strategy 1: VENDOR MATCHING                            │   │
    │   │   ┌─────────────────────────────────────────────┐       │   │
    │   │   │ WiFi Vendor == BLE Vendor?                   │       │   │
    │   │   │ Apple == Apple? ✓ MATCH                      │       │   │
    │   │   └─────────────────────────────────────────────┘       │   │
    │   │                                                          │   │
    │   │   Strategy 2: TEMPORAL CORRELATION                       │   │
    │   │   ┌─────────────────────────────────────────────┐       │   │
    │   │   │ WiFi appeared at 14:30:05                    │       │   │
    │   │   │ BLE appeared at  14:30:07                    │       │   │
    │   │   │ Time delta: 2 seconds ✓ LIKELY SAME DEVICE   │       │   │
    │   │   └─────────────────────────────────────────────┘       │   │
    │   │                                                          │   │
    │   │   Strategy 3: NAME PATTERNS                              │   │
    │   │   ┌─────────────────────────────────────────────┐       │   │
    │   │   │ BLE Name: "John's iPhone"                    │       │   │
    │   │   │ WiFi SSID Probe: "JohnHome"                  │       │   │
    │   │   │ Pattern match: "John" ✓ POSSIBLE LINK        │       │   │
    │   │   └─────────────────────────────────────────────┘       │   │
    │   │                                                          │   │
    │   └─────────────────────────────────────────────────────────┘   │
    │                                                                  │
    └──────────────────────────────────────────────────────────────────┘
```

## Correlation Algorithm (v2.0.7)

```
    ┌─────────────────────────────────────────────────────────────────┐
    │              CORRELATION PARAMETERS                             │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   TIME_WINDOW     = 15s      Temporal correlation window        │
    │   VENDOR_WEIGHT   = 40pts    Matching OUI vendor                │
    │   TIME_WEIGHT     = 35pts    Temporal proximity (scaled)        │
    │   RSSI_WEIGHT     = 0pts     DISABLED (BLE RSSI is fake)        │
    │   APPEARANCE_WEIGHT = 10pts  Both MACs randomized or permanent  │
    │   MIN_CONFIDENCE  = 35pts    Minimum score for match            │
    │                                                                 │
    │   Key insight: hcitool lescan does NOT provide real RSSI.       │
    │   All BLE devices report hardcoded -70dBm.                      │
    │   RSSI scoring is disabled to prevent false positives.          │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

### Real Timestamp Capture

Timestamps are captured DURING the scan, not at parse time:

```bash
    # WiFi probe arrives at 14:30:05 → timestamp = 14:30:05
    # BLE advert arrives at 14:30:07 → timestamp = 14:30:07
    #
    # Temporal delta = 2 seconds → HIGH correlation likelihood
```

This enables accurate temporal correlation even though BLE floods discoveries at scan start while WiFi probes trickle in over time.

### Tested Results

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                    FIELD TEST RESULTS                           │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   60-second scan:                                               │
    │   ├── WiFi devices:   2                                         │
    │   ├── BLE devices:    70                                        │
    │   └── Correlations:   14 (0-2 second temporal proximity)        │
    │                                                                 │
    │   All correlations show real temporal proximity between         │
    │   WiFi probes and BLE advertisements - not false positives.     │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

---

## MAC Randomization Detection

```
    ┌─────────────────────────────────────────────────────────────────┐
    │           DETECTING RANDOMIZED MAC ADDRESSES                    │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   MAC Address Structure:                                        │
    │                                                                 │
    │      X2:XX:XX:XX:XX:XX   ◄── Second character determines type   │
    │      │                                                          │
    │      └── If 2, 6, A, or E = LOCALLY ADMINISTERED (randomized)   │
    │          If 0, 4, 8, or C = GLOBALLY UNIQUE (real MAC)          │
    │                                                                 │
    │   Examples:                                                     │
    │   ┌────────────────────┬─────────────────────────────────────┐ │
    │   │ A2:B3:C4:D5:E6:F7  │ Randomized (2nd char = 2)           │ │
    │   │ 3E:1A:2B:3C:4D:5E  │ Randomized (2nd char = E)           │ │
    │   │ 00:1A:2B:3C:4D:5E  │ Real MAC (2nd char = 0) - Apple     │ │
    │   │ DC:A6:32:XX:XX:XX  │ Real MAC (2nd char = C) - Raspberry │ │
    │   └────────────────────┴─────────────────────────────────────┘ │
    │                                                                 │
    │   HUGINN marks randomized MACs and focuses correlation on       │
    │   vendor + temporal + behavioral patterns instead.              │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## OUI Vendor Lookup

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                    OUI DATABASE LOOKUP                          │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   MAC: AA:BB:CC:DD:EE:FF                                        │
    │         └──┬──┘                                                 │
    │            │                                                    │
    │            ▼                                                    │
    │   ┌─────────────────┐                                           │
    │   │  OUI: AA:BB:CC  │                                           │
    │   └────────┬────────┘                                           │
    │            │                                                    │
    │            ▼                                                    │
    │   ┌─────────────────────────────────────────────────────────┐  │
    │   │  /lib/hak5/oui.txt (38,379 vendors)                      │  │
    │   ├─────────────────────────────────────────────────────────┤  │
    │   │  AABBCC    Apple, Inc.                                   │  │
    │   │  001A2B    Motorola                                      │  │
    │   │  DCA632    Raspberry Pi                                  │  │
    │   │  ...                                                     │  │
    │   └─────────────────────────────────────────────────────────┘  │
    │            │                                                    │
    │            ▼                                                    │
    │   Result: "Apple, Inc."                                         │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## Sample Correlation Report

```
    ┌─────────────────────────────────────────────────────────────────┐
    │            HUGINN IDENTITY CORRELATIONS                         │
    │            Generated: 2024-01-03 15:45:22                       │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   WiFi devices captured: 23                                     │
    │   BLE devices captured:  47                                     │
    │                                                                 │
    │   ═══════════════════════════════════════════════════════════   │
    │                     VENDOR MATCHES                              │
    │   ═══════════════════════════════════════════════════════════   │
    │                                                                 │
    │   ┌─────────────────────────────────────────────────────────┐  │
    │   │  Vendor: Apple, Inc.                                     │  │
    │   │  ├── WiFi: A2:B3:C4:D5:E6:F7 (randomized)                │  │
    │   │  │       Probing: "JohnHome", "Starbucks"                │  │
    │   │  │                                                       │  │
    │   │  └── BLE:  DC:A6:32:11:22:33                             │  │
    │   │           Name: "John's iPhone 14"                       │  │
    │   │                                                          │  │
    │   │  CORRELATION: HIGH CONFIDENCE                            │  │
    │   │  >> Likely same person's device <<                       │  │
    │   └─────────────────────────────────────────────────────────┘  │
    │                                                                 │
    │   ┌─────────────────────────────────────────────────────────┐  │
    │   │  Vendor: Samsung Electronics                             │  │
    │   │  ├── WiFi: 6E:7F:8A:9B:0C:1D (randomized)                │  │
    │   │  │       Probing: "NETGEAR-5G", "Home_WiFi"              │  │
    │   │  │                                                       │  │
    │   │  └── BLE:  44:55:66:77:88:99                             │  │
    │   │           Name: "Galaxy S23"                             │  │
    │   │                                                          │  │
    │   │  CORRELATION: HIGH CONFIDENCE                            │  │
    │   └─────────────────────────────────────────────────────────┘  │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## Capture Flow

```
    ┌───────┐                                                  ┌───────┐
    │ START │                                                  │  END  │
    └───┬───┘                                                  └───▲───┘
        │                                                          │
        ▼                                                          │
    ┌─────────────┐                                                │
    │ Set Duration│  (default: 60 seconds)                         │
    └──────┬──────┘                                                │
           │                                                       │
           ▼                                                       │
    ┌─────────────┐     ┌─────────────┐                           │
    │ Start WiFi  │────▶│ Start BLE   │                           │
    │ Capture     │     │ Capture     │                           │
    └──────┬──────┘     └──────┬──────┘                           │
           │                   │                                   │
           └─────────┬─────────┘                                   │
                     │                                             │
                     ▼                                             │
           ┌─────────────────┐                                     │
           │  Wait Duration  │  [12/60s] WiFi: 5 | BLE: 23         │
           │  Show Progress  │                                     │
           └────────┬────────┘                                     │
                    │                                              │
                    ▼                                              │
           ┌─────────────────┐                                     │
           │ Stop Captures   │                                     │
           └────────┬────────┘                                     │
                    │                                              │
                    ▼                                              │
           ┌─────────────────┐                                     │
           │ Run Correlation │                                     │
           │    Engine       │                                     │
           └────────┬────────┘                                     │
                    │                                              │
                    ▼                                              │
           ┌─────────────────┐                                     │
           │  Save Report    │──────────────────────────────────────┘
           │  to Loot Dir    │
           └─────────────────┘
```

## Requirements

- WiFi Pineapple Pager with:
  - wlan1mon (monitor mode interface)
  - hci0 (BLE adapter)
  - tcpdump
  - hcitool

## Output Files

```
/root/loot/huginn/
├── huginn_report_YYYYMMDD_HHMMSS.txt   # Full correlation report
├── wifi_probes_YYYYMMDD_HHMMSS.txt     # Raw WiFi probe data
└── ble_devices_YYYYMMDD_HHMMSS.txt     # Raw BLE device data
```

## Use Cases

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                      USE CASES                                  │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                 │
    │   1. PHYSICAL PENETRATION TESTING                               │
    │      ┌─────────────────────────────────────────────────────┐   │
    │      │  Track target's device through building despite     │   │
    │      │  MAC randomization. Follow them floor to floor.     │   │
    │      └─────────────────────────────────────────────────────┘   │
    │                                                                 │
    │   2. SURVEILLANCE DETECTION                                     │
    │      ┌─────────────────────────────────────────────────────┐   │
    │      │  Identify if the same device keeps appearing near   │   │
    │      │  you (possible tail). Different MACs, same BLE.     │   │
    │      └─────────────────────────────────────────────────────┘   │
    │                                                                 │
    │   3. PRIVACY RESEARCH                                           │
    │      ┌─────────────────────────────────────────────────────┐   │
    │      │  Demonstrate how MAC randomization can be bypassed  │   │
    │      │  for academic papers and awareness.                 │   │
    │      └─────────────────────────────────────────────────────┘   │
    │                                                                 │
    │   4. RED TEAM OPERATIONS                                        │
    │      ┌─────────────────────────────────────────────────────┐   │
    │      │  Maintain persistent device tracking during long    │   │
    │      │  engagements. Know when target arrives/leaves.      │   │
    │      └─────────────────────────────────────────────────────┘   │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

## LED Indicators

```
    ┌──────────────┬─────────────────────┐
    │    Color     │      Meaning        │
    ├──────────────┼─────────────────────┤
    │  🔵 Blue     │  Scanning           │
    │  🟠 Orange   │  Correlating        │
    │  🟢 Green    │  Complete           │
    └──────────────┴─────────────────────┘
```

## Author

HaleHound
