Frogport Central Command v1.7
================================

Roles:
- Vault Keeper: one vault inventory + one packager. Requests Producers when its vault needs stock. Pulses once for matching Consumer requests.
- Producer: one packager. Produces one configured item string. Optional inventory reporting only; never requests items.
- Consumer: watches one or more inventories. Each watched inventory uses fixed capacity 1280 and sends exactly one package request at/below 50%, then rearms after rising above 50%.
- Overseer: monitor/dashboard and network configuration editor.

New in v1.7:
- Shutdown/reboot persistence for runtime status.
- Nodes save their latest status, recent log, and important runtime state to /Frogport/data.
- Consumers persist their one-package request latch, so a reboot does not immediately spam duplicate requests while the inventory is still below 50%.
- Overseer persists its known node list and recent network log.
- startup.lua now auto-resumes: normal startup installs missing files, checks the configured role, and immediately starts that role.
- Use `startup menu` to open the Frogport shell/update menu.
- Use `startup update` to force update from GitHub.
- Menus now use scrollable arrow-key selection where practical.

Startup behavior:
- `startup` = install missing files, then immediately run configured role.
- `startup menu` = open the scrollable Frogport shell.
- `startup update` = force-update files from GitHub.
- `startup run` = install missing files and run role.

GitHub raw base:
https://raw.githubusercontent.com/TenchiRyokoMuyo/Create-Computercraft-Inventory-System/main

Install:
Upload all files to the root of the ComputerCraft computer, then run:
startup

To update later:
startup menu
or:
startup update
