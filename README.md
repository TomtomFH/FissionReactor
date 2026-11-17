# ComputerCraft Fission Reactor Control System (Minecraft)

**A ComputerCraft app for fission reactor monitoring and control**

I made this so you don't blow up your reactor a million times like I did. Now you can monitor it easily and keep your base safe from explosions and radiation that could kill you!

This Lua UI runs on monitors or terminals to watch & control your reactor safely with real-time monitoring and automatic safety features.

## ✨ Key Features

- **Real-time monitoring**: Heat Rate, Damage %, Temperature (°C by default)
- **Resource level bars**: Coolant, Fuel, Heated Coolant, Waste
- **Wireless support**: Control your reactor remotely via wireless modem
- **One-click reactor control**: Easy ONLINE/OFFLINE toggle button
- **Intelligent safety system**: Automatic shutdown with optional auto-restart
- **Fixed safety limits**: Safety thresholds are hardcoded and cannot be changed in the UI or config

## 🎨 Status Color Guide

- **Lime Green** = Reactor is running normally
- **Red** = Manually turned off by user
- **Orange** = Automatically shut down by safety system (will auto-restart when safe)
- **Pink** = Emergency shutdown due to high danger (requires manual restart)

## ⚠️ Safety System

### Normal Safety Shutdown (Auto-restart enabled)

The system will automatically shut down and restart when these conditions are met:

- **Coolant** < 10%
- **Heated Coolant** > 99%
- **Waste** > 99%

### High Danger Shutdown (Manual restart required)

Critical conditions that require your attention:

- **Any reactor damage** (> 0%) triggers an immediate emergency shutdown and requires a manual restart

 > **Note**: Normal coolant/heated coolant/waste trips auto-restart once all readings are safe. Any detected damage is an emergency trip and requires a manual restart. Safety thresholds are fixed in `reactor.lua`.

## 📁 File Structure

```
reactor.lua        # Main UI and fixed safety control logic
update.lua         # Updates the installed program files from GitHub
reactor-modem.lua  # Wireless modem bridge (reactor-side)
functions.lua      # Reactor API adapter and peripheral interface
config.lua         # User-editable settings
```

## 🔧 Troubleshooting

| Problem                           | Solution                                                                          |
| --------------------------------- | --------------------------------------------------------------------------------- |
| **Reactor stuck in Pink state**   | Lower temperature or damage below thresholds, then press ONLINE                   |
| **Reactor stuck in Orange state** | Wait for all safety conditions to return to normal ranges, or disable Safety Mode |
| **Values showing 0 or n/a**       | Make sure reactor cables are connected and enabled                                |
| **No monitor detected**           | App automatically falls back to computer terminal                                 |
| **Safety system not working**     | Check that all sensor methods return valid numbers                                |
| **Wireless shows no data**        | Ensure both computers use the same `MODEM_CHANNEL` and modems are attached        |

> **💡 Tip**: For best display experience, use a **5x3 monitor** setup (5 monitors wide, 3 monitors tall)

## 🎥 Demo Video

[![Reactor Control Demo](https://img.youtube.com/vi/eTAx5YGsN68/0.jpg)](https://youtu.be/eTAx5YGsN68)

## 📜 Installation

1. **Download and run the installer** on your computer:

   ```lua
   wget https://ccfr.moma.dev install
   ```
   ```lua
   install
   ```

2. **Choose your installation type**:
   - **[1] Display Computer** — The computer that shows the UI
   - **[2] Modem Bridge** — Only for wireless setups, runs next to the reactor

3. **If you chose Display Computer**, the installer asks how it connects:
   - **[1] Cable** — Logic Adapter is cabled directly to this computer
   - **[2] Wireless** — Uses a Wireless Modem Bridge PC

4. **Reboot** with `Ctrl+R` — the system starts automatically


### Requirements

- **ComputerCraft** computer
- **Monitor** (optional, 5x3 recommended for best display)
- **Fission reactor** with Logic Adapter

### Wireless Requirements

For wireless mode you need **two computers**, each with a **Wireless Modem**:

| Computer | Location | Installer Option |
| --- | --- | --- |
| **Modem Bridge** | Next to the reactor (Logic Adapter attached) | Option **2** |
| **Display Computer** | Anywhere | Option **1** → Wireless |

Both computers must use the same `MODEM_CHANNEL` in `config.lua` (default: `42`).

### Temperature Unit

By default temperature is shown in **Celsius**. To use **Fahrenheit**, set `TEMP_IN_F = true` in `config.lua`.

Safety checks are fixed in code: coolant below 10%, heated coolant above 99%, waste above 99%, or any damage above 0%. Fuel and temperature are not safety trip conditions. Burn rate is displayed below the ONLINE/OFFLINE button. Run `update` on the computer to install the latest program files without overwriting your connection settings in `config.lua`.
