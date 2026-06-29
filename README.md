# PartyGames

Multiplayer card and board game platform built with Godot 4. Supports LAN discovery via UDP broadcast and ENet multiplayer.

## Games
- **Whot!** — Nigerian card game (2-4 players)
- **Battleship** — Classic ship placement + turn-based firing (2 players)
- **Chess** — Full rule enforcement including castling, en passant, promotion (2 players)
- **Checkers** — American draughts with forced captures and kings (2 players)

## Architecture
- `scripts/network/NetworkManager.gd` — ENet host/client + UDP room discovery
- `scripts/network/RoomState.gd` — Room metadata and game selection
- `scripts/ui/UIKit.gd` — Programmatic UI component factory
- `scripts/ui/AudioManager.gd` — Procedural SFX synthesis
- `scripts/games/*/Engine.gd` — Server-authoritative game logic (one per game)

## Multiplayer
- Host creates a room → broadcasts via UDP on port 7778
- Clients scan for rooms on port 7778, connect via ENet on port 7777
- Host is authoritative for all game state
- Clients receive serialized snapshots — no sensitive state leaks

## Build
Install Android template: `godot4 --editor --path PROJECT --script res://install_android.gd`
