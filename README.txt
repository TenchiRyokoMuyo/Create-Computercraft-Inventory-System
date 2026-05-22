Frogport Central Command
=========================

Install:
1. Upload this zip's contents to the root of each ComputerCraft computer.
2. Reboot or run: startup
3. On first boot, choose the role:
   1 = Vault Keeper
   2 = Producer
   3 = Consumer
   4 = Overseer

Files:
/startup.lua
/Frogport/FrogportLib.lua
/Frogport/FrogportVaultKeeper.lua
/Frogport/FrogportProducer.lua
/Frogport/FrogportConsumer.lua
/Frogport/FrogportOverseer.lua

Network:
Default channel: 6610

Role summary:
Vault Keeper:
- One vault inventory.
- One packager.
- One configured item string.
- Requests Producers when its vault is below Full.
- Pulses its packager when a matching Consumer requests restock.

Producer:
- One packager.
- One configured item string.
- May have an inventory for reporting only.
- Never requests items.
- Pulses its packager when matching Vault Keeper requests production.

Consumer:
- One watched inventory.
- One configured item string.
- Requests matching Vault Keepers when below Full.

Overseer:
- Passive dashboard.
- Shows Vault Keepers, Producers, Consumers, statuses, percentages, and events.

Inventory states:
Full             95%-100%  no requests
Stock Needed     75%-94%   request every 5 seconds
Low              50%-74%   request every 3 seconds
Critically Low   10%-49%   request every 1 second
Empty            0%-9%     emergency/constant requests until back to 75%+

Reset config:
Delete /Frogport/data/role.cfg to choose a new role.
Delete a role cfg in /Frogport/data/ to rerun that role's setup.
