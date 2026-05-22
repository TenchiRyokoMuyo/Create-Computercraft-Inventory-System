Frogport Central Command v1.1
=============================

ComputerCraft logistics controller for Create packagers, item vaults, producers, consumers, and overseer displays.

Install
-------
Upload startup.lua to the root of a ComputerCraft computer and reboot/run:

startup

The startup file now checks for missing Frogport files and downloads them from:
https://github.com/TenchiRyokoMuyo/Create-Computercraft-Inventory-System

If files already exist, startup leaves them alone.
To force refresh the Frogport files from GitHub, run:

startup update

Requirements
------------
ComputerCraft HTTP must be enabled if using the automatic installer.
If HTTP is disabled, upload the full zip contents manually.

Files
-----
/startup.lua
/Frogport/FrogportLib.lua
/Frogport/FrogportVaultKeeper.lua
/Frogport/FrogportProducer.lua
/Frogport/FrogportConsumer.lua
/Frogport/FrogportOverseer.lua
/README.txt

Roles
-----
Vault Keeper:
- Watches one configured item in one vault inventory.
- Requests matching producers based on inventory state.
- Pulses one local packager when a matching consumer requests restock.

Producer:
- Produces one configured item.
- Pulses one local packager when a matching Vault Keeper requests production.
- Reports inventory if an inventory is attached.
- Never requests items.

Consumer:
- Watches one configured item in one attached inventory.
- Requests matching Vault Keepers based on inventory state.

Overseer:
- Displays Vault Keepers, Producers, Consumers, statuses, percentages, and recent requests.

Shared Inventory States
-----------------------
Full             95%-100%   no requests
Stock Needed     75%-94%    request every 5 seconds
Low              50%-74%    request every 3 seconds
Critically Low   10%-49%    request every 1 second
Empty             0%-9%     emergency constant requests until back to 75%+
