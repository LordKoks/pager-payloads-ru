# Virtual Pager Enhancer - v2.3.2
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

## Overview

Virtual Pager Enhancer is a lightweight client-side enhancement for the Virtual Pager web interface that improves **loot management**, **visual customization** and **System information monitoring**.

## How to use

When running the payload, you can press the **“A”** button to enable or disable the Virtual Pager Enhancer.
After enabling or disabling the enhancer, press any other button to exit the script.

Once finished, HARD refresh the Virtual Pager web page. If everything worked correctly, you should see new menu items added to the navigation bar.

## Functionality


* 📂⬇️ **Loot Enumeration & Selective Downloads** 

    Discovers available loot folders from `/root/loot` and allows downloading individual folders using the existing `/api/files/zip/root/loot/{FOLDER}` endpoint. While the Virtual Pager UI only exposes this API for `/root/loot/handshakes`, the enhancer extends its use to any loot folder, eliminating the need to download the entire loot directory.

* 🎨 **Pager Skinner**
  Enables customization of the Virtual Pager interface by:

  * Changing background colors
  * Setting custom background images
  * Set pager color
  * Set custom pager image

* 💻 **System Info**
  Displays key system metrics, including:

  * Disk usage
  * RAM usage
  * CPU usage

* 🚀 **Update Payloads**
  Update your payloads from the official github repo


