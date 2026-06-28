# HumiliateGod

A medieval strategy game built with the Godot Engine, featuring multiple unit types, building construction, and resource management across multiple levels.

## Game Overview

HumiliateGod is a 2D strategy game where players manage resources, build structures, and train various medieval units to complete objectives across multiple levels. The game features multiple factions with unique unit types including warriors, archers, monks, and lancers.

## Features

- **Multiple Unit Types**: Warriors, Archers, Monks, Lancers, and Pawns
- **Building System**: Houses, Towers, Barracks, Archery Ranges, Castle, Monastery
- **Resource Management**: Gold, Wood, Meat
- **5 Faction Colors**: Black, Blue, Purple, Red, Yellow
- **5 Campaign Levels**: Progress through increasingly challenging missions
- **Audio System**: Background music, sound effects, and voiceovers

## Project Structure

```
├── Archers/          - Archer units and arrow projectiles
├── Audio/            - Music, sound effects, voiceovers
├── Levels/           - Game level definitions (level1-level5)
├── Main/             - Core game systems, menus, UI
├── Materiels/        - Game objects (explosions, fire, mines, etc.)
├── Textures/         - All game graphics and sprites
├── Tutorials/        - Tutorial levels
├── buildings/        - Building definitions
├── unit/             - All unit types (knights, goblins, etc.)
└── project.godot     - Godot project file
```

## Getting Started

### Requirements
- Godot Engine 4.x

### Running the Game
1. Open the project in Godot 4.x
2. Click Play or press F5
3. Select a level from the main menu

## Controls

- **Left Click**: Select units/buildings
- **Right Click**: Move/Attack command
- **Mouse Drag**: Box selection (for selecting multiple units)
- **Keyboard Shortcuts**: See in-game settings menu

## Units

| Unit | Description |
|------|-------------|
| Warrior | Melee combat unit |
| Archer | Ranged attack unit |
| Monk | Healing support unit |
| Lancer | Heavy cavalry unit |
| Pawn | Resource gatherer/builder |

## Buildings

| Building | Function |
|----------|----------|
| House | Unit production |
| Tower | Defense structure |
| Barracks | Warrior training |
| Archery | Archer training |
| Castle | Main base |
| Monastery | Monk training |

## License

This project is for educational/personal use.