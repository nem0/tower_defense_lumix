# Asteroids Lumix

A top-down arcade shooter demo built using the Lumix game engine.

## Description

Pilot a ship through waves of asteroids, dodge impacts, and pick up powerups to stay alive. The game features a starfield backdrop, particle effects, and simple UI for score, lives, and boosts.

## Screenshots

![Asteroids Screenshot](screenshot.png)

## Features

- Top-down ship movement with boost and inertia
- Asteroid waves with large and small variants
- Powerups: Rapid Fire, Shield, and +1 Life
- Particle effects for exhaust, hits, and explosions

## Assets

- 3D models from Quaternius Ultimate Platformer Pack (CC0). See [asteroids/models/License.txt](models/License.txt).
- Particle effects from Kenney Particle Pack (CC0). See [asteroids/particles/License.txt](particles/License.txt).

## Project Structure

- `asteroids.lua`: Main game script
- `asteroids.unv`: Scene
- `models/`: Environment, ship, and pickup models
- `particles/`: Particle effects and materials
- `screenshot.png`: Project screenshot
- `chess/math.lua`: Shared math helpers used by the script

## License

This project is licensed under the MIT License for the code (see LICENSE at the repository root). The assets are licensed under Creative Commons Zero (CC0), as detailed in [asteroids/models/License.txt](models/License.txt) and [asteroids/particles/License.txt](particles/License.txt).
