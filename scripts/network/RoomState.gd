extends Node
## RoomState — tracks the selected game and shared room metadata.
## Lives outside NetworkManager so games can mutate room-level data without
## touching the network layer.

signal room_metadata_changed()
signal selected_game_changed(game_id: String)
signal player_ready_changed(peer_id: int, ready: bool)

const SUPPORTED_GAMES: Array = [
	{
		"id": "whot",
		"name": "Whot! 🇳🇬",
		"description": "Nigerian card classic. 2–4 players.",
		"min_players": 2,
		"max_players": 4,
		"icon": "res://assets/icons/whot.png",
		"scene": "res://scenes/games/whot/Whot.tscn",
	},
	{
		"id": "battleship",
		"name": "Battleship",
		"description": "Place your fleet. Sink theirs.",
		"min_players": 2,
		"max_players": 2,
		"icon": "res://assets/icons/battleship.png",
		"scene": "res://scenes/games/battleship/Battleship.tscn",
	},
	{
		"id": "chess",
		"name": "Chess",
		"description": "Classic 2-player strategy.",
		"min_players": 2,
		"max_players": 2,
		"icon": "res://assets/icons/chess.png",
		"scene": "res://scenes/games/chess/Chess.tscn",
	},
	{
		"id": "checkers",
		"name": "Checkers",
		"description": "Draughts. Jump to win.",
		"min_players": 2,
		"max_players": 2,
		"icon": "res://assets/icons/checkers.png",
		"scene": "res://scenes/games/checkers/Checkers.tscn",
	},
]

var selected_game_id: String = ""
var player_ready: Dictionary = {} # peer_id -> bool

func get_game_def(game_id: String) -> Dictionary:
	for g in SUPPORTED_GAMES:
		if g["id"] == game_id:
			return g
	return {}

func get_all_games() -> Array:
	return SUPPORTED_GAMES

func select_game(game_id: String) -> void:
	if selected_game_id == game_id:
		return
	selected_game_id = game_id
	selected_game_changed.emit(game_id)

func clear_selection() -> void:
	selected_game_id = ""
	player_ready.clear()
	selected_game_changed.emit("")

func set_ready(peer_id: int, ready: bool) -> void:
	player_ready[peer_id] = ready
	player_ready_changed.emit(peer_id, ready)

func all_players_ready(player_ids: Array) -> bool:
	if player_ids.is_empty():
		return false
	for pid in player_ids:
		if not player_ready.get(pid, false):
			return false
	return true