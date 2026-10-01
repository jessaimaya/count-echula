# Count Echula

A cute-spooky rhythm runner made with [Rive](https://rive.app), and my entry for the **Rive Halloween Challenge 2026**.

On Halloween night, Count Echula (a vampire turned into a small bat wearing oversized headphones) flies down a trick-or-treat street that's invisible in the dark. He can only see by echolocation, and his sonar only fires on the beat. Catch the candy that sits on the music to send out sonar pulses that light up the street. Dodge the garlic you can't see, and grab as much candy as you can before the song ends.

*Echula* = echo + Dracula.

## How to play

| Gesture | Action |
| --- | --- |
| Swipe left / right | Change lane. Swipe into a candy's lane on its beat to catch it (PERFECT / GOOD) |
| Tap | Send a small manual ping around the bat |
| Tap on the title / results screen | Start / retry (the first tap also turns on the sound) |

Each candy you catch fires the sonar on the beat and shows the next stretch of the street before the fog closes in again. If you miss a candy, you're flying blind.

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
game/       Rive CLI project: RML scene, Luau scripts, WGSL shaders, audio and fonts
web/        Small web page that loads the .riv
scripts/    Local build + serve helper
```

## Credits

Game design, code and art direction by [@jessaimaya](https://github.com/jessaimaya).

Fonts: [Creepster](https://fonts.google.com/specimen/Creepster) and [Fredoka](https://fonts.google.com/specimen/Fredoka), both under the SIL Open Font License (see `game/assets/fonts/`).

#rivehalloweenchallenge
