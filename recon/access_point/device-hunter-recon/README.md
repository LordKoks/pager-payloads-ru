# Device Hunter – Recon Auto-Hunt (Pager)
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

A targeted Device Hunter payload for the Hak5 Pager that automatically hunts a network based on Recon data, using RocketGod’s Device Hunter core.

This payload is designed to be launched from **Recon → Access Points** and immediately begin hunting a target AP without manual MAC entry.

---

## ✨ What This Does

- Uses **Recon data** to automatically select a target AP
- Launches **Device Hunter** immediately (no menus)
- Provides real-time **signal strength feedback** using:
  - LEDs
  - Audio tones
  - Vibration
- Stops cleanly with the **A button**

---

## 🔍 How Target Selection Works

Because the Pager firmware **does not pass the selected AP from the Recon UI into payloads**, this payload selects a target using the best available backend data:

1. **Recon database (`recon.db`)**
   - Attempts to locate the most recently seen access point
2. **Recon API fallback**
   - Uses the first AP returned by `_pineap RECON APS`

This ensures the payload always starts hunting *something* immediately, without requiring user input.

---

## ⚠️ Important Behaviour (Client Mode)

If your Pager is connected to Wi-Fi in **client mode**, your main hub/router will:

- Be seen continuously
- Always have the newest `last_seen` timestamp
- Dominate Recon’s backend data

As a result, **the payload will usually hunt your connected hub**, even if you select a different SSID in the Recon UI.

This is expected behaviour and not a bug.

### Why this happens

- The Recon UI selection is **visual only**
- The firmware does **not expose “selected AP” context** to payloads
- The payload can only use Recon’s stored data, not UI state

---

## 📁 Installation

Place the payload here: root@pager:~/payloads/recon/access_point# 
run :cd /mmc/root/payloads

mkdir -p recon/access_point/device_hunter
nano recon/access_point/device_hunter/payload.sh
chmod +x recon/access_point/device_hunter/payload.sh

paste payload.sh into nano.

complete

Happy Hunting!!!!


