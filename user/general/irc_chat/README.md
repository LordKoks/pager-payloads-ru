# IRC Chat – Hak5 Pineapple Pager Payload
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

**Author:** Hackazillarex  
**Version:** 1.0  
**Platform:** Hak5 Pineapple Pager   
**Protocol:** IRC 

---

## 📡 Overview

**IRC Chat** is an interactive payload for the **Hak5 Pineapple Pager** that allows you to connect directly to an IRC channel, view incoming messages on the Pager screen, and reply using the built‑in **TEXT_PICKER** interface.

This payload runs **continuously** until you exit it from the Pager UI and requires **no additional packages** to be installed.

---

## ✨ Features

- Choose your **IRC nickname** at runtime
- Choose the **IRC channel** to join
- Connects to **irc.oftc.net**
- Displays incoming messages on the Pager screen using `LOG`
- Color‑coded output:
  - **White** – chat messages & general info
  - **Green** – status events & sending messages
  - **Red** – errors, disconnects, cancellations
- 5‑second delay before prompting a reply
- Reply to messages using **TEXT_PICKER**
- Automatic reconnect on disconnect
- Runs continuously until payload is stopped

---

## 🌐 IRC Network

- **Server:** `irc.oftc.net`
- **Port:** `6667`
- **Web client (for desktop/mobile):** 
  👉 https://webchat.oftc.net

You can use the web client to chat in the same channel while interacting with the Pager.

---

## 🧰 Requirements

- Hak5 Pineapple Pager
- Active internet connection

> ❗ No `opkg` packages or external IRC clients are required.  
> The payload uses a raw IRC connection via `/dev/tcp`.

