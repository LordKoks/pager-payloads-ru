## 🛡️ WHAT'S NEW: TRIG_MAC v2.2.0
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

### Geospatial Intelligence & Transparency Update

While v1.2.0 focused on core radio stability, **v2.2.0** transforms the Pager into a mobile wardriving and tracking hub with full GPS integration and refined operator feedback.

---

### 🛰️ ADVANCED GEOSPATIAL LOGGING

The biggest leap from v1.2.0 is the **Integrated Location Engine**.

* **Dual-Column CSV:** Logs now automatically split into `Latitude` and `Longitude` columns. No more manual data cleaning—just import the log directly into **Google Earth Pro** or **GIS software**.
* **GPSD Integration:** Optimized to work with high-gain USB receivers (like the VFAN). The script now manages the `gpsd` daemon and serial baud rates (9600/115200) automatically.
* **GPS Check:** Location data is verified every scan cycle. If a lock is lost, it logs `0.000 0.000` to maintain file integrity without crashing the loop.

### 🤫 INTELLIGENT ALERTING (SILENT HITS)

v1.2.0 would either chime or be silent. v2.0 introduces **Blackout Awareness**:

* **120-Second Cooldown:** After a target is hit and the alarm sounds, the system enters a "blackout" period to prevent audio fatigue.
* **Live Feedback:** During the blackout, hits are still processed and logged! The OLED will display `SILENT HIT` in yellow/gray, letting the operator see real-time detections without drawing attention with sound or LEDs.

### 💀 TRANSPARENT "NUKE" LOGIC

The "Wipe DB" function has been overhauled for better system visibility.

* **Task Reporting:** Instead of silently killing processes, the script now reports exactly what it is cleaning up (e.g., `TCPDUMP STOPPED`, `BT SCAN STOPPED`).
* **Safety Sync:** Re-engineered the startup to kill rogue `gpspipe` or `tcpdump` instances from failed previous runs, ensuring the radio is 100% fresh before arming.

### 🕹️ UPDATED OPERATOR CONTROLS

| Input | Action | New in v2.0 |
| --- | --- | --- |
| **UP** | **Add SSID** | Same tactical input |
| **DOWN** | **Add BLE MAC** | MAC Picker optimized |
| **LEFT** | **Add WiFi MAC** | MAC Picker optimized |
| **B (Back)** | **SYSTEM MENU** | **Added Exit Logic:** Choose to Purge DB or Exit Script |
| **A (Select)** | **DEPLOY** | **Mode Select:** Choose between **Live Feed** or **Background Mode** |

---

### 🚀 DEPLOYMENT & EXTRACTION

* **Live Feed Mode:** Displays a scrolling log of detections and GPS coordinates directly on the Pager screen.
* **Background Mode:** Arms the device and exits to the main dashboard, allowing the Pager to act as a "black box" logger in a pocket or vehicle.
* **Loot Path:** Logs are now organized by date: `/root/loot/TRIG_MAC/hits_YYYY-MM-DD.csv`.

---
