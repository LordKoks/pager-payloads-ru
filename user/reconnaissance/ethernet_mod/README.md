Ethernet Mod Nmap Recon Payload
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

Author: Hackazillarex
Version: 2.0
Category: Fast Network Reconnaissance
Platform: Hak5 devices / Linux (Bash)
Interface: USB Ethernet (Glitch Mod / non‑GMO compatible)

📌 Overview

The Ethernet Mod Nmap Recon Payload is a speed‑optimized reconnaissance script designed to quickly profile a wired network using a USB Ethernet adapter.

The payload performs:

Automatic Ethernet interface bring‑up via DHCP

Local network discovery

Identification of the gateway and up to 4 additional live hosts

A single‑pass, high‑speed Nmap scan of the top 10 TCP ports

Clean, per‑host output written to a timestamped loot file

The focus is speed over depth, making it ideal for quick situational awareness during initial access or drop‑and‑run operations.

⚡ Features

🚀 Fast recon using aggressive Nmap timing

🔌 USB Ethernet adapter detection and validation

🌐 Gateway + 5 total hosts (gateway + 4 LAN devices)

📊 Top 10 TCP ports per host

🧠 Single Nmap scan for minimal execution time

🗂 Structured loot output

👁 Optional automatic log viewer launch

💡 Compatible with non‑GMO / Glitch Mod environments

🛠 Requirements
Hardware

USB Ethernet adapter

Default USB ID: 0bda:8152 (Realtek-based)

How It Works

USB Adapter Check

Verifies the Ethernet adapter is present

Prompts the user if not detected

Interface Initialization

Brings up eth1

Acquires IP via DHCP

Network Discovery

Identifies gateway and subnet

Performs ARP-based host discovery

Selects up to 4 additional live hosts

Fast Port Scan

Single Nmap invocation

Top 10 TCP ports

Aggressive timing (-T5, minimal retries)

Result Parsing

Groups open ports by host

Writes clean, readable output

📜 License & Disclaimer

This script is provided for educational and authorized security testing purposes only.
The author assumes no responsibility for misuse.
