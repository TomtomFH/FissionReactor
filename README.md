# Fission Reactor / Induction Matrix Control

A CC:Tweaked controller that detects a connected Mekanism multiblock and installs the matching display.

## Install

1. Connect the Fission Reactor Logic Adapter or an Induction Port to the computer through Wired Modems and Networking Cable.
2. Optionally connect an Advanced Monitor.
3. Run:
   ```lua
   wget https://ccfr.moma.dev install
   install
   ```
4. The installer detects the connected multiblock and installs its controller as `startup.lua`.
5. Reboot the computer.

If both a reactor and matrix are connected, the installer currently prioritizes the reactor.

## Controllers

- **Fission Reactor:** existing reactor display and safety controls.
- **Induction Matrix:** live energy, capacity and fill percentage display. Above 99% full, the failsafe activates redstone output on all six sides; at or below 99%, it clears.

## Updating

Use the controller's UPDATE button where available, or run `update`. The updater redetects the connected multiblock, installs the matching controller, preserves `config.lua`, and reboots.

## Reactor safety limits

- Coolant below 10%: automatic shutdown.
- Heated coolant above 99%: automatic shutdown.
- Waste above 99%: automatic shutdown.
- Any reactor damage above 0%: emergency shutdown and recovery countdown.

The reactor failsafe outputs redstone on all six sides while shutdown is active. The Induction Matrix failsafe outputs redstone on all six sides while its energy level is above 99%.

## Credits

Original project by **MohammedMMC**: https://github.com/MohammedMMC/FissionReactor-CC
