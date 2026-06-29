extends RefCounted
## Whot! — Nigerian card game engine.
## 5 shapes x 12 numbers = 60 cards. Special: 1(Hold On), 2(Pick2), 5(Pick3), 8(Gen.Market), 14(Whot).

class_name WhotEngine

const SHAPES := ["circle", "triangle", "cross", "square", "star"]
const NUMBERS := [1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14]

var deck: Array = []
var discard: Array = []
var players: Array = []
var turn_index: int = 0
var pending_action: Dictionary = {}
var game_over: bool = false
var winner: int = 0
var last_move: Dictionary = {}
var log: Array = []

func _init() -> void: reset()

func reset() -> void:
	deck = []
	for shape in SHAPES:
		for n in NUMBERS:
			deck.append({"shape": shape, "number": n})
	deck.shuffle()
	discard = []
	players = []
	turn_index = 0
	pending_action = {}
	game_over = false
	winner = 0
	last_move = {}
	log = []

func add_player(peer_id: int, name: String) -> void:
	players.append({"peer_id": peer_id, "name": name, "hand": [], "last_card_called": false})

func start_game() -> void:
	var hand_size := 5 if players.size() <= 3 else 4
	for p in players:
		p["hand"] = []
		for i in hand_size: p["hand"].append(_draw_from_deck())
	discard.append(_draw_from_deck())
	_rescue_if_special_top()
	turn_index = 0
	log.append("Game started with %d players." % players.size())

func top_card() -> Dictionary:
	if discard.is_empty(): return {}
	return discard[-1]

func player_hand(peer_id: int) -> Array:
	for p in players:
		if p["peer_id"] == peer_id: return p["hand"]
	return []

func current_player() -> Dictionary:
	if players.is_empty(): return {}
	return players[turn_index]

func can_play(peer_id: int, card: Dictionary) -> bool:
	if game_over: return false
	if current_player().get("peer_id") != peer_id: return false
	if pending_action.has("type") and pending_action.get("from_peer") != peer_id:
		match pending_action.get("type"):
			"pick_two": return int(card.get("number", -1)) == 2
			"pick_three": return int(card.get("number", -1)) == 5
		return false
	var top = top_card()
	if card.get("number") == 14: return true
	if card.get("shape") == top.get("shape"): return true
	if int(card.get("number", -1)) == int(top.get("number", -2)): return true
	return false

func play_card(peer_id: int, card_index: int, chosen_shape: String = "") -> Dictionary:
	var result := {"ok": false, "reason": ""}
	if game_over: result["reason"] = "Game over"; return result
	var player = _find_player(peer_id)
	if player.is_empty(): result["reason"] = "Unknown player"; return result
	if player["peer_id"] != current_player().get("peer_id"): result["reason"] = "Not your turn"; return result
	if card_index < 0 or card_index >= player["hand"].size(): result["reason"] = "Bad card index"; return result
	var card: Dictionary = player["hand"][card_index]
	if pending_action.has("type"):
		match pending_action.get("type"):
			"pick_two":
				if int(card.get("number", -1)) != 2: result["reason"] = "Must defend with Pick Two or Pick Three"; return result
				pending_action["count"] = int(pending_action.get("count", 2)) + 2
				pending_action["from_peer"] = peer_id
			"pick_three":
				if int(card.get("number", -1)) != 5: result["reason"] = "Must defend with Pick Three"; return result
				pending_action["count"] = int(pending_action.get("count", 3)) + 3
				pending_action["from_peer"] = peer_id
			"hold_on", "general_market": result["reason"] = "Nothing to defend"; return result
		_remove_and_play(player, card_index, chosen_shape)
		result["ok"] = true
		result["defended"] = true
		return result
	var top = top_card()
	var valid := false
	if int(card.get("number")) == 14: valid = true
	elif card.get("shape") == top.get("shape"): valid = true
	elif int(card.get("number")) == int(top.get("number")): valid = true
	if not valid: result["reason"] = "Card doesn't match top"; return result
	_remove_and_play(player, card_index, chosen_shape)
	result["ok"] = true
	return result

func _remove_and_play(player: Dictionary, card_index: int, chosen_shape: String) -> void:
	var card: Dictionary = player["hand"][card_index]
	player["hand"].remove_at(card_index)
	var top = top_card()
	var played_card = card.duplicate()
	if int(card.get("number")) == 14:
		if chosen_shape == "" or not SHAPES.has(chosen_shape):
			chosen_shape = top.get("shape", "circle") if not top.is_empty() else "circle"
		played_card["shape"] = chosen_shape
	discard.append(played_card)
	last_move = {"peer": player["peer_id"], "card": played_card}
	match int(card.get("number")):
		1: pending_action = {"type": "hold_on", "count": 0, "from_peer": player["peer_id"]}; _advance_turn(1)
		2: pending_action = {"type": "pick_two", "count": 2, "from_peer": player["peer_id"]}; _advance_turn(1)
		5: pending_action = {"type": "pick_three", "count": 3, "from_peer": player["peer_id"]}; _advance_turn(1)
		8: pending_action = {"type": "general_market", "count": 1, "from_peer": player["peer_id"]}; _advance_turn(1)
		14: _advance_turn(1)
		_: _advance_turn(1)
	if player["hand"].is_empty():
		game_over = true
		winner = player["peer_id"]
		log.append("%s wins!" % player["name"])

func _advance_turn(steps: int) -> void:
	turn_index = (turn_index + steps) % players.size()
	if turn_index < 0: turn_index += players.size()

func draw_one_for_current() -> Dictionary:
	var result := {"ok": false, "reason": "Game over"}
	if game_over: return result
	var player = current_player()
	player["hand"].append(_draw_from_deck())
	if pending_action.has("type"):
		log.append("%s drew %d card(s)." % [player["name"], pending_action.get("count", 1)])
		pending_action = {}
		_advance_turn(1)
	result["ok"] = true
	return result

func apply_pending_pick(peer_id: int) -> Dictionary:
	var result := {"ok": false, "reason": ""}
	if game_over: return result
	if current_player().get("peer_id") != peer_id: result["reason"] = "Not your turn"; return result
	if not pending_action.has("type"):
		var player = current_player()
		player["hand"].append(_draw_from_deck())
		_advance_turn(1)
		result["ok"] = true
		return result
	if pending_action.get("from_peer") == peer_id: result["reason"] = "You started the action"; return result
	var n = int(pending_action.get("count", 1))
	var player = current_player()
	for i in n: player["hand"].append(_draw_from_deck())
	log.append("%s picked up %d card(s)." % [player["name"], n])
	pending_action = {}
	_advance_turn(1)
	result["ok"] = true
	result["picked"] = n
	return result

func call_last_card(peer_id: int) -> bool:
	for p in players:
		if p["peer_id"] == peer_id:
			if p["hand"].size() == 1:
				p["last_card_called"] = true
				log.append("%s calls LAST CARD!" % p["name"])
				return true
	return false

func _draw_from_deck() -> Dictionary:
	if deck.is_empty():
		if discard.size() <= 1: return {"shape": "circle", "number": 1}
		var top: Dictionary = discard.pop_back()
		deck = discard.duplicate(); discard = [top]; deck.shuffle()
	if deck.is_empty(): return {"shape": "circle", "number": 1}
	return deck.pop_back()

func _rescue_if_special_top() -> void:
	var top = top_card()
	if top.is_empty(): return
	var n := int(top.get("number", -1))
	if n == 2 or n == 5 or n == 8 or n == 14:
		deck.append(discard.pop_back()); deck.shuffle()
		discard.append(deck.pop_back())
		_rescue_if_special_top()

func _find_player(peer_id: int) -> Dictionary:
	for p in players:
		if p["peer_id"] == peer_id: return p
	return {}

func serialize_for_peer(peer_id: int) -> Dictionary:
	var players_view = []
	for p in players:
		var entry = {"peer_id": p["peer_id"], "name": p["name"], "count": p["hand"].size(), "last_card_called": p["last_card_called"]}
		if p["peer_id"] == peer_id: entry["hand"] = p["hand"].duplicate(true)
		players_view.append(entry)
	return {"deck_count": deck.size(), "top_card": top_card(), "turn_index": turn_index, "players": players_view, "pending_action": pending_action.duplicate(true), "game_over": game_over, "winner": winner, "last_move": last_move.duplicate(true), "log_tail": log.slice(max(0, log.size()-8), log.size())}