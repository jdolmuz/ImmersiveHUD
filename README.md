# Immersive HUD

Your HUD fades away while you explore and comes back when you need it. Built for **World of Warcraft: Forever** (interface 16001).

## How it works
- Start moving, and after a moment the HUD slowly fades out.
- It comes back instantly when you:
  - enter combat
  - click or target something
  - have an enemy targeted
  - cast a spell
  - type in chat
  - hover the mouse over a hidden element
  - drop to low health
- Stopping doesn't bring the HUD back unless you turn that option on.

## Elements you can fade
Each element has its own toggle:
- Action bars (main, extra, stance and pet bars)
- Player and pet frames
- Target and focus frames
- Party and raid frames
- Buffs and debuffs
- Cooldown Manager
- Micro menu and bag bar
- XP and reputation bars
- Quest / objective tracker
- Chat (windows, tabs, buttons and input box)
- Minimap

The minimap, quest tracker, and party and raid frames stay visible by default.

## Install
Copy the `ImmersiveHUD` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then `/reload`.

## Settings
Open the settings with `/ihud`, or go to **Options → AddOns → Immersive HUD**. You can adjust:
- how long you move before the fade starts
- how fast the HUD fades out and back in
- how faded "hidden" is
- which events bring the HUD back

There are also keybinds to keep the HUD visible, snooze fading for 5 minutes, or turn auto-fade on and off.

## Notes
- It only changes transparency, so it's safe to use in combat. Faded buttons and keybinds still work.
- Holding a mouse button to turn the camera doesn't count as a click.
- Fading pauses while Edit Mode is open.

## Commands
| Command | Effect |
|---|---|
| `/ihud` | Open settings |
| `/ihud on` / `off` | Turn auto-fade on or off |
| `/ihud pin` | Keep the HUD visible |
| `/ihud snooze [minutes]` | Keep the HUD visible for a few minutes (default 5), then resume fading |
| `/ihud snooze off` | Cancel a snooze early |
| `/ihud toggle <element>` | Turn fading on or off for one element |
| `/ihud frames` | List the HUD frames the add-on found |
| `/ihud errors` | Copy an error report |

## License
Open source under the [MIT License](LICENSE). Provided as is, without warranty or support.
