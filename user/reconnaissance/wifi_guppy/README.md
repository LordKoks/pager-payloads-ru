<h2 align="center">WiFi_Guppy</h2>
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
<p align="center">
<img alt="WiFi Guppy Logo" src="https://github.com/user-attachments/assets/9b82170d-665f-49b0-9bb1-e465694b9e7d" />
</p>

    Payload name: WiFi Guppy
    Author: JustSomeTrout (Trout / troot.)
    Developed for Firmware version 1.0.4
    Category: Reconnaissance
    Wi-Fi channel congestion visualizer.
    Focuses on Wi-Fi channel load, not individual networks.
    *No 🐟 were harmed while surveying the RF reef*

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Overview

**WiFi Guppy** is a lightweight reconnaissance payload that
provides a clear, visual snapshot of how busy each Wi-Fi channel is.

**WiFi Guppy answers the question**:

> *Which channels are crowded — and which ones are calm?*

The result is fast Wi-Fi situational awareness without digging through raw scan data.

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Features

- **Tri-band scanning**: 2.4 GHz, 5 GHz, and 6 GHz
- Aggregates access point presence per channel
- **Grouped by band** for clear Wi-Fi situational awareness
- Visual bar-graph representation of channel congestion
- Color-coded output for quick interpretation:
    - 🟢 Low congestion (1-3 APs)
    - 🟡 Moderate congestion (4-7 APs)
    - 🔴 Heavy congestion (8+ APs)

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## How It Works

1. Creates a temporary managed interface on phy1 (tri-band radio)
2. Performs an active scan using `iwinfo` (sends probe requests)
3. Parses band and channel information from scan results
4. Groups channels by frequency band (2.4 GHz, 5 GHz, 6 GHz)
5. Counts access points per channel
6. Displays relative channel load as a capped bar graph
7. Cleans up temporary interface on exit

The payload automatically handles interface creation and cleanup.

**Note:** This uses active scanning which transmits probe requests. It is not a passive/listen-only tool.

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Example Output

```
=== 2.4 GHz ===
Ch   1 ██████████ (10)
Ch   6 ████████ (8)
Ch  10 ██████ (6)
Ch  11 ████████ (8)

=== 5 GHz ===
Ch  36 ████ (4)
Ch  48 ██ (2)
Ch 149 ████████ (8)

=== 6 GHz ===
Ch   5 █ (1)
Ch 133 █ (1)
```

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Installation

1. Copy the `wifi_guppy` folder into:
   ```
   /root/payloads/user/reconnaissance/
   ```

2. The payload will appear in the Pager's payload menu under Reconnaissance.
