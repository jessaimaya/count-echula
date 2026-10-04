# Count Echula

A cute-spooky rhythm runner made with [Rive](https://rive.app), and my entry for the **Rive Halloween Challenge 2026**.

On Halloween night, Count Echula (a vampire turned into a small bat wearing oversized headphones) flies down a trick-or-treat street that's invisible in the dark. He can only see by echolocation, and his sonar only fires on the beat. Catch the candy that sits on the music to send out sonar pulses that light up the street. Dodge the garlic and wooden stakes you can't see, and grab as much candy as you can before the song ends.

*Echula* = echo + Dracula.

## How to play

| Gesture | Keys | Action |
| --- | --- | --- |
| Swipe left / right | ← / → or A / D | Change lane. Swipe into a candy's lane on its beat to catch it (PERFECT / GOOD) |
| Swipe on the title screen | ← / → | Pick a record |
| Tap on the title / results screen | Enter | Play / retry (the first tap also turns on the sound) |
| Pause button (top right) | Esc / P | Pause: resume or go back to the record shelf |

Each candy you catch fires the sonar on the beat and shows the next stretch of the street before the fog closes in again. Catching candy is the only way to see: if you miss one, you're flying blind.

Three records to pick from:

- **Side A, Echula Theme**: the easy one, with a foggy bridge.
- **Side B, Funky Counting**: disco-funk with a "Cold Moon" breakdown that freezes the street.
- **Side C, Werewolf Wipeout**: surf-rock with a blackout, then the street keeps speeding up until the last hit.

## Built with

- **Rive CLI**: the scene, HUD, title and results screens are written in Rive Markup Language (RML)
- **GPU Canvas**: WGSL shaders for the sonar outlines, fog, night sky and glitch effects (`game/shaders/`)
- **Scripting**: game logic in Luau, including the beat clock, beatmap, gestures and rules (`game/world.luau`, `game/lib/`)
- **Data Binding and State Machines**: they drive the HUD and the title → play → results flow

## Run it locally

The repo includes a prebuilt game file (`game/build/count-echula.riv`). To play it in your browser, serve the repo root with any static server:

```sh
python3 -m http.server 8000
```

Then open <http://localhost:8000/web/>.

### Rebuild from source

You need the [Rive CLI](https://rive.app/docs/cli/overview).

```sh
rive game --verify    # check that the project compiles
rive game --test      # run the logic tests
scripts/web-dev.sh    # build game/build/count-echula.riv and serve it on your LAN
```

## Project layout

```
game/       Rive CLI project: RML scene, Luau scripts, WGSL shaders, art, audio and fonts
svg/        Source drawings, converted into Rive artboards by scripts/svg2rml.py
web/        Small web page that loads the .riv
scripts/    Build + serve helper, SVG → RML converter, house cut-out tool
```

## Credits

Game design, code and art direction by [@jessaimaya](https://github.com/jessaimaya).

Music: three songs generated on [yueai.ai](https://yueai.ai) with [YuE2](https://github.com/multimodal-art-projection/YuE) (M-A-P / HKUST). #YuE2

Fonts: [Creepster](https://fonts.google.com/specimen/Creepster) and [Fredoka](https://fonts.google.com/specimen/Fredoka), both under the SIL Open Font License (see `game/assets/fonts/`).

#rivehalloweenchallenge
