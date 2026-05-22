Frogport Central Command v1.4
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
