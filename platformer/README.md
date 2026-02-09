# Platformer Lumix

A small 3D side-on platformer demo built with the Lumix game engine.

## Description

This demo demonstrates character movement and jumping, simple platforming mechanics, moving platforms, interactable levers, checkpoints, collectibles (coins + extra lives), basic hazards (traps/spikes), and a minimal UI for lives and score.

## Screenshot

![Platformer Screenshot](screenshot.png)

## Features

- Side-on player controller
- Walk and jump with simple physics (no sprint)
- Holding `Shift` reduces movement speed (slow walk)
- Moving platforms and collision detection
- Levers / interactable objects (`E` to interact)
- Checkpoints, coins, extra lives, and UI updates
- Hazards: traps and spikes
- Pause/menu and restart via the in-game menu (and respawn when dead)

## Controls

### Keyboard
- **A / D**: Move left / right
- **W / Space**: Jump
- **Shift**: Reduce movement speed (slow)
- **E**: Interact with levers/objects
- **R**: Respawn when dead (requires remaining lives)
- **M**: Toggle menu / pause

## Assets

The demo uses freely-available asset packs (models, sprites, and particles). See the `models/`, `audio/`, and `gui/` subfolders for any license files that accompany assets.

## Project Structure

- `platformer.unv`: Scene
- `README.md`: This file
- `models/`: 3D models and textures
- `audio/`: Sound effects and music
- `gui/`: UI sprites and fonts
- `scripts/`: Lua scripts used by the scene
- `screenshot.png`: Project screenshot

## License

This project code is licensed under the MIT License (see the repository `LICENSE` at the root). Asset licenses vary by file — see any `License.txt` files in the asset subfolders for details.
