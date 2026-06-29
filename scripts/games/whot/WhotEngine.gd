extends RefCounted
## Whot! — Nigerian card game engine.
## 5 shapes × 12 numbers = 60 cards. Special cards: 1 (Hold On), 2 (Pick Two),
## 5 (Pick Three), 8 (General Market), 14 (Whot — choose shape).
## Defense: Pick Two can be defended by another Pick Two (or Pick Three); Pick Three
## can be defended by another Pick Three. 1s do NOT defend (they only skip).
##
## Defense stacking keeps the penalty count: e.g. opponent drops a Pick Two, you
## defend with another Pick Two, next player must pick FOUR.

class_name WhotEngine

const SHAPES := ["circle", "triangle", "cross", "square", "star"]
# Per-shape number composition: 1..5, 7..8, 10..14
const NUMBERS := [1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14]

var deck: Array = [] # Array of {"shape":String,"number":int}
var discard: Array = [] # discard pile (last is top)
var players: Array = [] # [{peer_id:int, name:String, hand:Array, last_card_called:bool}]
var turn_index: int = 0
var pending_action: Dictionary = {} # {"type":String, "count":int, "from_peer":int}
var game_over: bool = false
var winner: int = 0 # peer_id
var last_move: Dictionary = {} # {"peer":int, "card":Dictionary, "shape_called":String|null}
var log: Array = [] # list of strings for action log

func _init() -> void:
	reset()

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
	# Deal 5 cards to each player (4 if more than 3 players)
	var hand_size := 5 if players.size() <= 3 else 4
	for p in players:
		p["hand"] = []
		for i in hand_size:
			p["hand"].append(_draw_from_deck())
	# Flip one card to start discard pile; if it's a special, leave it (players will react)
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

# ----------------------------------------------------------------------
# Card play
# ----------------------------------------------------------------------

func can_play(peer_id: int, card: Dictionary) -> bool:
	if game_over: return false
	if current_player().get("peer_id") != peer_id: return false
	if pending_action.has("type") and pending_action.get("from_peer") != peer_id:
		# Defending a pending action — must be a defense card
		match pending_action.get("type"):
			"pick_two":
				return int(card.get("number", -1)) == 2
			"pick_three":
				return int(card.get("number", -1)) == 5
		return false
	# Normal play — match top card's shape OR number OR is a Whot (14)
	var top := top_card()
	if card.get("number") == 14: return true
	if card.get("shape") == top.get("shape"): return true
	if int(card.get("number", -1)) == int(top.get("number", -2)): return true
	return false

func play_card(peer_id: int, card_index: int, chosen_shape: String = "") -> Dictionary:
	var result := {"ok": false, "reason": ""}
	if game_over: result["reason"] = "Game over"; return result
	var player = _find_player(peer_id)
	if player.is_empty():
		result["reason"] = "Unknown player"; return result
	if player["peer_id"] != current_player().get("peer_id"):
		result["reason"] = "Not your turn"; return result
	if card_index < 0 or card_index >= player["hand"].size():
		result["reason"] = "Bad card index"; return result
	var card: Dictionary = player["hand"][card_index]

	# If pending action, this is a defense
	if pending_action.has("type"):
		match pending_action.get("type"):
			"pick_two":
				if int(card.get("number", -1)) != 2:
					result["reason"] = "Must defend with Pick Two or Pick Three"; return result
				pending_action["count"] = int(pending_action.get("count", 2)) + 2
				pending_action["from_peer"] = peer_id
			"pick_three":
				if int(card.get("number", -1)) != 5:
					result["reason"] = "Must defend with Pick Three"; return result
				pending_action["count"] = int(pending_action.get("count", 3)) + 3
				pending_action["from_peer"] = peer_id
			"hold_on", "general_market":
				# Shouldn't happen — these end the turn naturally
				result["reason"] = "Nothing to defend"; return result
		_remove_and_play(player, card_index, chosen_shape)
		result["ok"] = true
		result["defended"] = true
		return result

	# Normal play
	var top := top_card()
	var valid := false
	if int(card.get("number")) == 14: valid = true
	elif card.get("shape") == top.get("shape"): valid = true
	elif int(card.get("number")) == int(top.get("number")): valid = true
	if not valid:
		result["reason"] = "Card doesn't match top"; return result

	_remove_and_play(player, card_index, chosen_shape)
	result["ok"] = true
	return result

func _remove_and_play(player: Dictionary, card_index: int, chosen_shape: String) -> void:
	var card: Dictionary = player["hand"][card_index]
	player["hand"].remove_at(card_index)
	# If it's a Whot (14), override shape
	var top := top_card()
	var played_card := card.duplicate()
	if int(card.get("number")) == 14:
		if chosen_shape == "" or not SHAPES.has(chosen_shape):
			chosen_shape = top.get("shape", "circle") if not top.is_empty() else "circle"
		played_card["shape"] = chosen_shape
	discard.append(played_card)
	last_move = {"peer": player["peer_id"], "card": played_card}

	# Apply special effect (number)
	match int(card.get("number")):
		1: # Hold On
			pending_action = {"type": "hold_on", "count": 0, "from_peer": player["peer_id"]}
			_advance_turn(1)
		2: # Pick Two
			pending_action = {"type": "pick_two", "count": 2, "from_peer": player["peer_id"]}
			_advance_turn(1)
		5: # Pick Three
			pending_action = {"type": "pick_three", "count": 3, "from_peer": player["peer_id"]}
			_advance_turn(1)
		8: # General Market
			pending_action = {"type": "general_market", "count": 1, "from_peer": player["peer_id"]}
			_advance_turn(1)
		14: # Whot — wild; no effect on turn
			_advance_turn(1)
		_:
			_advance_turn(1)

	# Win check
	if player["hand"].is_empty():
		game_over = true
		winner = player["peer_id"]
		log.append("%s wins!" % player["name"])

func _advance_turn(steps: int) -> void:
	turn_index = (turn_index + steps) % players.size()
	if turn_index < 0: turn_index += players.size()

# ----------------------------------------------------------------------
# Draw / pick cards
# ----------------------------------------------------------------------

func draw_one_for_current() -> Dictionary:
	"""Current player draws a single card (used for general market 'paying the price')."""
	if game_over: return {"ok": false, "reason": "Game over"}
	var player = current_player()
	if pending_action.has("type") and pending_action.get("from_peer") == player["peer_id"]:
		# No pending action for ourselves
		pass
	player["hand"].append(_draw_from_deck())
	# After drawing, end the pending action and advance turn
	if pending_action.has("type"):
		log.append("%s drew %d card(s)." % [player["name"], pending_action.get("count", 1)])
		pending_action = {}
		_advance_turn(1)
	return {"ok": true}

func apply_pending_pick(peer_id: int) -> Dictionary:
	"""Called when a player cannot / will not defend the pending pick. They pick up."""
	var result := {"ok": false, "reason": ""}
	if game_over: return result
	if current_player().get("peer_id") != peer_id: result["reason"] = "Not your turn"; return result
	if not pending_action.has("type"):
		# No pending action — single draw (used at game start)
		var player = current_player()
		player["hand"].append(_draw_from_deck())
		_advance_turn(1)
		result["ok"] = true
		return result
	if pending_action.get("from_peer") == peer_id:
		result["reason"] = "You started the action"; return result
	var n := int(pending_action.get("count", 1))
	var player = current_player()
	for i in n:
		player["hand"].append(_draw_from_deck())
	log.append("%s picked up %d card(s)." % [player["name"], n])
	pending_action = {}
	_advance_turn(1)
	result["ok"] = true
	result["picked"] = n
	return result

func pass_turn_after_hold(peer_id: int) -> Dictionary:
	"""Used when a Hold On was played and the affected player needs to skip."""
	if current_player().get("peer_id") != peer_id: return {"ok": false}
	if pending_action.get("type") == "hold_on" and pending_action.get("from_peer") != peer_id:
		log.append("%s missed turn (Hold On)." % current_player()["name"])
		pending_action = {}
		_advance_turn(1)
		return {"ok": true}
	return {"ok": false}

# ----------------------------------------------------------------------
# Last-card call
# ----------------------------------------------------------------------

func call_last_card(peer_id: int) -> bool:
	for p in players:
		if p["peer_id"] == peer_id:
			if p["hand"].size() == 1:
				p["last_card_called"] = true
				log.append("%s calls LAST CARD!" % p["name"])
				return true
	return false

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

func _draw_from_deck() -> Dictionary:
	if deck.is_empty():
		# Reshuffle discard pile (except top) into deck
		if discard.size() <= 1:
			# No cards left at all — synthesize
			return {"shape": "circle", "number": 1}
		var top: Dictionary = discard.pop_back()
		deck = discard.duplicate()
		discard = [top]
		deck.shuffle()
	if deck.is_empty():
		return {"shape": "circle", "number": 1}
	var c: Dictionary = deck.pop_back()
	return c

func _rescue_if_special_top() -> void:
	# If the initial top card is a Pick 2 or Pick 3, redraw to avoid stuck game.
	var top := top_card()
	if top.is_empty(): return
	var n := int(top.get("number", -1))
	if n == 2 or n == 5 or n == 8 or n == 14:
		# Put it back in deck, redraw
		deck.append(discard.pop_back())
		deck.shuffle()
		discard.append(deck.pop_back())
		_rescue_if_special_top()

func _find_player(peer_id: int) -> Dictionary:
	for p in players:
		if p["peer_id"] == peer_id: return p
	return {}

# ----------------------------------------------------------------------
# Serialization
# ----------------------------------------------------------------------

func serialize_for_peer(peer_id: int) -> Dictionary:
	"""Hide other players' hands. Show counts only."""
	var players_view := []
	for p in players:
		var entry := {
			"peer_id": p["peer_id"],
			"name": p["name"],
			"count": p["hand"].size(),
			"last_card_called": p["last_card_called"],
		}
		if p["peer_id"] == peer_id:
			entry["hand"] = p["hand"].duplicate(true)
		players_view.append(entry)
	return {
		"deck_count": deck.size(),
		"top_card": top_card(),
		"turn_index": turn_index,
		"players": players_view,
		"pending_action": pending_action.duplicate(true),
		"game_over": game_over,
		"winner": winner,
		"last_move": last_move.duplicate(true),
		"log_tail": log.slice(max(0, log.size() - 8), log.size()),
	}