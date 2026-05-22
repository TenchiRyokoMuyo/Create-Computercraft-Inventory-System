Frogport Central Command v1.6
================================

Install the contents of this zip at the root of each ComputerCraft computer.
Then run:

  startup

startup.lua is a shell-style launcher. It can:
- Run the configured role
- Change role
- Install missing files from GitHub
- Force-update files from GitHub
- Reset the local role config
- List peripherals
- Open CraftOS shell

Roles:
- Vault Keeper: watches one vault inventory and one item, requests Producers when stock falls below Full, and pulses its packager for matching Consumer requests.
- Producer: listens for matching Producer requests and pulses one packager. It may report inventory but never requests items.
- Consumer: watches multiple inventories independently and requests matching Vault Keepers for each watched inventory/item.
- Overseer: dashboard plus remote config editor by node name.

Inventory states:
- Full: 95%-100%, no request
- Stock Needed: 75%-94%, request every 5 seconds
- Low: 50%-74%, request every 3 seconds
- Critically Low: 10%-49%, request every 1 second
- Empty: 0%-9%, emergency constant mode until back to Stock Needed or higher

v1.4 capacity calculation:
- Uses getItemLimit(slot) when available instead of assuming size() * 64.
- Adds capacity modes:
  1. slot_limits: sum getItemLimit(slot) for every slot.
  2. matching_slots: only slots currently holding the configured item.
  3. occupied_slots: all currently occupied slots.
  4. filled_plus_one: matching item slots plus one extra stack.
- Manual capacity override still exists and wins if set above 0.

For Create item vaults, start with slot_limits. If the modded inventory peripheral still reports strange virtual capacity, use the Overseer or local setup to change capacity mode or set a manual full capacity.


Version 1.5 notes:
- Consumer restocking is now one-shot. Each watched Consumer inventory sends exactly one CONSUMER_REQUEST when its percent is at or below 50% by default.
- A matching Vault Keeper responds with exactly one redstone pulse to its packager.
- The Consumer request latch rearms only after that watched inventory rises above the request threshold, then later falls to or below it again.
- Vault Keepers still use the five inventory states to request Producers for their own vault refill behavior.


Version 1.6 notes:
- Consumer watched inventory readings now always use a fixed effective capacity of 1280 items.
- Consumer percentage is calculated as item_count / 1280 * 100 for every watched inventory entry.
- Consumer setup and Overseer remote editing no longer ask for Consumer capacity mode/override; Vault Keepers and Producers still use the inventory API capacity modes.
