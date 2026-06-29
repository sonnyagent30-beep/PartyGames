extends RefCounted
## Battleship engine — placement phase, then alternating shots.
## Per player: ships, shots_fired, shots_received.
## Host-authoritative. Clients receive serialized snapshots.

class_name BattleshipEngine

const SIZE := 10
const SHIP_FLEET := [
	{"name": "Carrier",    "size": 5},
	{"name": "Battleship", "size": 4},
	{"name": "Destroyer",  "size": 3},
	{"name": "Submarine",  "size": 3},
	{"name": "Patrol Boat","size": 2},
]

var players: Dictionary = {} # peer_id (1, 2) -> player state dict
var phase: String = "placement" # "placement", "battle", "over"
var turn: int = 0 # peer_id whose turn
var winner: int = 0

func _init() -> void: reset()

func reset() -> void:
	players = {}
	phase = "placement"
	turn = 0
	winner = 0

func register_player(peer_id: int) -> void:
	if players.has(peer_id): return
	players[peer_id] = {"ships": [], "shots_fired": {}, "shots_received": {}, "ready": false}

func is_registered(peer_id: int) -> bool: return players.has(peer_id)
func all_registered(peer_ids: Array) -> bool:
	for p in peer_ids:
		if not players.has(p): return false
	return true

func place_ship(peer_id: int, ship_name: String, cells: Array) -> bool:
	if phase != "placement": return false
	if not players.has(peer_id): return false
	var p = players[peer_id]
	for s in p["ships"]:
		if s["name"] == ship_name: return false
	var def := _ship_def(ship_name)
	if def == null: return false
	if cells.size() != def["size"]: return false
	for cell in cells:
		if not (cell is Vector2i): return false
		var v: Vector2i = cell
		if v.x < 0 or v.x >= SIZE or v.y < 0 or v.y >= SIZE: return false
	if not _is_contiguous(cells): return false
	for existing in p["ships"]:
		for ec in existing["cells"]:
			for nc in cells:
				if ec == nc: return false
	p["ships"].append({"name": ship_name, "size": def["size"], "cells": cells, "hits": 0, "sunk": false})
	return true

func auto_place(peer_id: int) -> bool:
	if phase != "placement": return false
	if not players.has(peer_id): return false
	players[peer_id]["ships"] = []
	var attempts := 0
	for def in SHIP_FLEET:
		while attempts < 200:
			attempts += 1
			var horizontal := randf() < 0.5
			var r := randi() % SIZE
			var c := randi() % SIZE
			var cells: Array = []
			for i in def["size"]:
				if horizontal: cells.append(Vector2i(r, c + i))
				else: cells.append(Vector2i(r + i, c))
			var ok := true
			for cell in cells:
				var v: Vector2i = cell
				if v.x < 0 or v.x >= SIZE or v.y < 0 or v.y >= SIZE: ok = false; break
			if not ok: continue
			if not _is_contiguous(cells): continue
			var overlap := false
			for existing in players[peer_id]["ships"]:
				for ec in existing["cells"]:
					for nc in cells:
						if ec == nc: overlap = true
			if overlap: continue
			if place_ship(peer_id, def["name"], cells): break
		else: return false
	return true

func all_ships_placed(peer_id: int) -> bool:
	if not players.has(peer_id): return false
	return players[peer_id]["ships"].size() == SHIP_FLEET.size()

func set_ready(peer_id: int) -> void:
	if not players.has(peer_id): return
	players[peer_id]["ready"] = true

func all_ready() -> bool:
	for k in players.keys():
		if not players[k]["ready"]: return false
	return players.size() >= 2

func maybe_start_battle(peer_ids: Array) -> bool:
	if phase != "placement": return false
	if not all_ready(): return false
	for pid in peer_ids:
		if not all_ships_placed(pid): return false
	phase = "battle"
	var pids = players.keys()
	pids.shuffle()
	turn = pids[0]
	return true

func fire(peer_id: int, r: int, c: int) -> Dictionary:
	var result := {"ok": false, "reason": ""}
	if phase != "battle": result["reason"] = "Not in battle phase"; return result
	if peer_id != turn: result["reason"] = "Not your turn"; return result
	var opp := 0
	for k in players.keys():
		if k != peer_id: opp = k; break
	if opp == 0: result["reason"] = "No opponent"; return result
	var key := "%d,%d" % [r, c]
	if players[peer_id]["shots_fired"].has(key): result["reason"] = "Already fired there"; return result
	if r < 0 or r >= SIZE or c < 0 or c >= SIZE: result["reason"] = "Out of bounds"; return result
	var hit := false
	var sunk_ship: String = ""
	for ship in players[opp]["ships"]:
		for cell in ship["cells"]:
			if cell == Vector2i(r, c):
				hit = true
				ship["hits"] += 1
				if ship["hits"] >= ship["size"]:
					ship["sunk"] = true
					sunk_ship = ship["name"]
				break
		if hit: break
	players[peer_id]["shots_fired"][key] = {"hit": hit, "sunk_ship": sunk_ship}
	players[opp]["shots_received"][key] = {"hit": hit, "from": peer_id}
	result["ok"] = true
	result["hit"] = hit
	result["sunk"] = sunk_ship != ""
	result["ship_name"] = sunk_ship
	var all_sunk := true
	for ship in players[opp]["ships"]:
		if not ship["sunk"]: all_sunk = false
	if all_sunk:
		phase = "over"
		winner = peer_id
		result["game_over"] = true
		result["winner"] = peer_id
		return result
	turn = opp
	result["next_turn"] = opp
	return result

func _ship_def(name: String) -> Dictionary:
	for s in SHIP_FLEET:
		if s["name"] == name: return s
	return {}

func _is_contiguous(cells: Array) -> bool:
	if cells.size() < 2: return true
	var first: Vector2i = cells[0]
	var horizontal := true
	var vertical := true
	for i in range(1, cells.size()):
		var prev: Vector2i = cells[i-1]
		var cur: Vector2i = cells[i]
		if cur.x != prev.x: horizontal = false
		if cur.y != prev.y: vertical = false
	if not horizontal and not vertical: return false
	if horizontal:
		var sorted = cells.duplicate(); sorted.sort_custom(func(a, b): return a.y < b.y)
		for i in range(1, sorted.size()):
			if sorted[i].y != sorted[i-1].y + 1: return false
	else:
		var sorted = cells.duplicate(); sorted.sort_custom(func(a, b): return a.x < b.x)
		for i in range(1, sorted.size()):
			if sorted[i].x != sorted[i-1].x + 1: return false
	return true

func serialize_for_peer(peer_id: int) -> Dictionary:
	var snap := {"phase": phase, "turn": turn, "winner": winner, "you": peer_id, "size": SIZE, "fleet": SHIP_FLEET}
	var players_view = {}
	for pid in players.keys():
		var entry = {}
		if pid == peer_id:
			entry["ships"] = players[pid]["ships"]
			entry["shots_received"] = players[pid]["shots_received"]
			entry["shots_fired"] = players[pid]["shots_fired"]
		else:
			entry["shots_fired"] = players[peer_id]["shots_fired"] if players.has(peer_id) else {}
			var sunk = []
			for ship in players[pid]["ships"]:
				if ship["sunk"]: sunk.append(ship["name"])
			entry["sunk_ships"] = sunk
		entry["ready"] = players[pid]["ready"]
		players_view[pid] = entry
	snap["players"] = players_view
	return snap