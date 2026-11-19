# Fission Reactor Control System

A ComputerCraft / CC:Tweaked program for monitoring and controlling a Mekanism Fission Reactor.

## Features

- Live reactor information and resource levels
- ONLINE / OFFLINE reactor control
- Automatic safety shutdowns
- Automatic recovery countdown after reactor damage clears
- Red warning text for active safety conditions
- Automatic update checker and updater

## Setup

- Build your Mekanism Fission Reactor.
- Attach a **Logic Adapter** to the reactor.
- Place an **Advanced Computer** nearby.
- Connect the Logic Adapter to the computer using **Wired Modems and Networking Cable**.
- Right-click the Wired Modems to activate them.
- (Optional) Connect an Advanced Monitor to the computer. A **5-wide by 3-high** monitor setup is recommended.
- Turn on the computer and open its terminal.
- Run these commands:

  ```lua
  wget https://ccfr.moma.dev install
  install
  ```

- The installer automatically installs the **wired Display Computer** version.
- When installation finishes, reboot the computer with `Ctrl+R`.
- The reactor control screen should start automatically.

## Updating

- Press **UPDATE** in the reactor control screen.
- The computer downloads the latest files and reboots when the update finishes.

## Safety Limits

- Coolant below 10%: automatic shutdown.
- Heated coolant above 99%: automatic shutdown.
- Waste above 99%: automatic shutdown.
- Any reactor damage above 0%: emergency shutdown. Once damage returns to 0%, a 60-second recovery countdown begins before automatic restart, provided the other safety readings are safe.

## Temperature

- Temperature is shown in Celsius by default.
- You can enable Fahrenheit by setting `TEMP_IN_F = true` in `config.lua`.

## Credits

- Original project and program by **MohammedMMC**: [github.com/MohammedMMC/FissionReactor-CC](https://github.com/MohammedMMC/FissionReactor-CC)
- This repository contains subsequent modifications and additions.
