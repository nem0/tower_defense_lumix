# Chess Lumix

A chess demo project built using the Lumix game engine.

## Description

This project sets up a chess board and pieces, supports mouse-driven drag & drop moves, and includes basic rule validation. It also includes a simple AI opponent (plays Black) plus Undo/Restart UI.

## Screenshots

![Chess Screenshot](screenshot.png)

## Features

- Drag & drop piece movement with board picking
- Basic chess move legality / check detection
- Simple AI opponent (Black)
- Undo and Restart buttons

## Getting Started

To run this project, you need the Lumix engine installed on your system.

1. Download and install Lumix from the official website: [Lumix Engine](https://github.com/nem0/LumixEngine/)
2. Open the repository folder in Lumix Studio.
3. Open [chess/chess.unv](chess.unv) and run the project from within the editor.

## Assets

The chess set comes from OpenGameArt and is licensed under Creative Commons Attribution 3.0 (CC BY 3.0). See [chess/license.txt](license.txt) for details.

- https://opengameart.org/content/chess-set (Author: elopez7 / Esteban Lopez)
- [UI Pack](https://kenney.nl/assets/ui-pack) (Author: Kenney)

## Project Structure

- `chess.lua`: Main game script
- `math.lua`: Small math helpers used by the script
- `Chess_Set/`: Chess set meshes/materials/textures
- `chess.unv`: Scene
- `screenshot.png`: Project screenshot

## License

This project is licensed under the MIT License for the code (see LICENSE at the repository root). The chess set assets are licensed under CC BY 3.0 (attribution required), as detailed in [chess/license.txt](license.txt).
