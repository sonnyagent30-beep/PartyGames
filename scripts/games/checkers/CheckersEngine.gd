extends RefCounted
## Checkers (American/English draughts — 8x8, forced captures, kings, multi-jumps).
## Pieces: r = red (host), b = black (client), R/B = kings, "" empty.
## Pieces live on dark squares only; we use row+col where (row+col) % 2 == 1.

class_name CheckersEngine

const SIZE := 8

var board: Array = [] # SIZE x SIZE
var turn: String = "r" # "r" or "b"
var game_over: bool = false
var winner: String = "" # "r", "b", "draw"
var move_history: Array = []
var must_jump_from: Array = [] # list of {r,c} cells that have jumps available

func _init() -> void:
	reset()

func reset() -> void:
	board = []
	for r in SIZE:
		var row := []
		for c in SIZE:
			row.append("")
		board.append(row)
	# Red on rows 0,1,2 (top); black on rows 5,6,7 (bottom)
	for r in [0, 1, 2]:
		for c in SIZE:
			if (r + c) % 2 == 1:
				board[r][c] = "r"
	for r in [5, 6, 7]:
		for c in SIZE:
			if (r + c) % 2 == 1:
				board[r][c] = "b"
	turn = "r"
	game_over = false
	winner = ""
	move_history = []
	_refresh_must_jump()

func piece_at(r: int, c: int) -> String:
	if r < 0 or r >= SIZE or c < 0 or c >= SIZE: return ""
	return board[r][c]

func is_dark_square(r: int, c: int) -> bool:
	return (r + c) % 2 == 1

func piece_color(p: String) -> String:
	if p == "": return ""
	return p.to_lower()

func is_king(p: String) -> bool:
	return p != "" and p == p.to_upper()

func opponent(color: String) -> String:
	return "b" if color == "r" else "r"

# ----------------------------------------------------------------------
# Move generation
# ----------------------------------------------------------------------

func jumps_from(r: int, c: int, color: String) -> Array:
	"""Return list of jump sequences. Each entry is Array of Vector2i (full path)."""
	var piece := piece_at(r, c)
	if piece == "" or piece_color(piece) != color: return []
	var dirs := [[-1,-1],[-1,1],[1,-1],[1,1]]
	if not is_king(piece):
		# Forward only: red moves down (positive), black moves up (negative)
		dirs = [[1,-1],[1,1]] if color == "r" else [[-1,-1],[-1,1]]
	var results: Array = []
	for d in dirs:
		var mr: int = r + int(d[0])
		var mc: int = c + int(d[1])
		var lr: int = r + 2 * int(d[0])
		var lc: int = c + 2 * int(d[1])
		if lr < 0 or lr >= SIZE or lc < 0 or lc >= SIZE: continue
		if not is_dark_square(lr, lc): continue
		var mid: String = piece_at(mr, mc)
		if mid != "" and piece_color(mid) == opponent(color) and piece_at(lr, lc) == "":
			results.append([Vector2i(lr, lc)])
	# Chain jumps
	var chained: Array = []
	for j_path in results:
		var last: Vector2i = j_path[-1]
		# Simulate: remove captured piece and move piece to last
		var captured_pos := Vector2i((r + last.x) / 2, (c + last.y) / 2)
		var saved_mid: String = board[captured_pos.x][captured_pos.y]
		var saved_piece: String = board[r][c]
		var promoted := false
		var landing_row := last.x
		board[captured_pos.x][captured_pos.y] = ""
		board[r][c] = ""
		var will_promote := (color == "r" and landing_row == SIZE - 1) or (color == "b" and landing_row == 0)
		if will_promote and not is_king(saved_piece):
			board[landing_row][last.y] = saved_piece.to_upper()
			promoted = true
		else:
			board[landing_row][last.y] = saved_piece
		# From landing, can we continue?
		if not promoted:
			var further := jumps_from(landing_row, last.y, color)
			for sub in further:
				var full_path: Array = j_path + sub
				chained.append(full_path)
		else:
			chained.append(j_path)
		# Restore
		board[captured_pos.x][captured_pos.y] = saved_mid
		board[r][c] = saved_piece
		board[landing_row][last.y] = ""
	if chained.is_empty():
		return results
	return chained

func simple_moves_from(r: int, c: int, color: String) -> Array:
	"""Non-capture moves for a piece."""
	if must_jump_from.size() > 0: return [] # forced capture
	var piece := piece_at(r, c)
	if piece == "" or piece_color(piece) != color: return []
	var dirs: Array = [[-1,-1],[-1,1],[1,-1],[1,1]]
	if not is_king(piece):
		dirs = [[1,-1],[1,1]] if color == "r" else [[-1,-1],[-1,1]]
	var moves: Array = []
	for d in dirs:
		var nr: int = r + int(d[0])
		var nc: int = c + int(d[1])
		if nr < 0 or nr >= SIZE or nc < 0 or nc >= SIZE: continue
		if not is_dark_square(nr, nc): continue
		if piece_at(nr, nc) == "":
			moves.append(Vector2i(nr, nc))
	return moves

func _refresh_must_jump() -> void:
	must_jump_from = []
	for r in SIZE:
		for c in SIZE:
			if piece_color(piece_at(r, c)) != turn: continue
			if not jumps_from(r, c, turn).is_empty():
				must_jump_from.append(Vector2i(r, c))

func moves_from(r: int, c: int) -> Array:
	"""Available move paths from (r,c). Each is Array of Vector2i."""
	var piece := piece_at(r, c)
	if piece == "" or piece_color(piece) != turn: return []
	var jumps := jumps_from(r, c, turn)
	if not jumps.is_empty():
		return jumps
	return [] # for m in simple_moves_from(r, c, turn): jumps.append([m])
	# return jumps

func all_legal_paths(color: String) -> Array:
	"""Return list of {from:Vector2i, path:Array of Vector2i} for color."""
	var result: Array = []
	for r in SIZE:
		for c in SIZE:
			if piece_color(piece_at(r, c)) != color: continue
			var paths := jumps_from(r, c, color)
			for p in paths:
				result.append({"from": Vector2i(r, c), "path": p})
	if not result.is_empty():
		return result
	# No jumps → simple moves
	for r in SIZE:
		for c in SIZE:
			if piece_color(piece_at(r, c)) != color: continue
			for m in simple_moves_from(r, c, color):
				result.append({"from": Vector2i(r, c), "path": [m]})
	return result

# ----------------------------------------------------------------------
# Apply move (server-side only)
# ----------------------------------------------------------------------

func apply_path(from: Vector2i, path: Array) -> bool:
	if game_over: return false
	if piece_color(piece_at(from.x, from.y)) != turn: return false
	var available := moves_from(from.x, from.y)
	var found_path: Array = []
	for p in available:
		if _paths_equal(p, path):
			found_path = p
			break
	if found_path.is_empty(): return false

	var piece := piece_at(from.x, from.y)
	var current := from
	for step in found_path:
		var nr: int = step.x
		var nc: int = step.y
		# Capture?
		if abs(nr - current.x) == 2 and abs(nc - current.y) == 2:
			var mr := (nr + current.x) / 2
			var mc := (nc + current.y) / 2
			board[mr][mc] = ""
		board[current.x][current.y] = ""
		board[nr][nc] = piece
		current = step
		# King promotion if landed on far row (and not already king)
		if piece == piece.to_lower():
			var promoted := false
			if turn == "r" and current.x == SIZE - 1:
				board[current.x][current.y] = "R"
				promoted = true
			elif turn == "b" and current.x == 0:
				board[current.x][current.y] = "B"
				promoted = true

	move_history.append({"from": from, "path": found_path.duplicate(true)})
	turn = opponent(turn)
	_refresh_must_jump()
	# Win detection
	var enemy_moves := all_legal_paths(turn)
	if enemy_moves.is_empty():
		game_over = true
		winner = "r" if turn == "b" else "b"
	# Mutual empty pieces
	var any_r := false
	var any_b := false
	for r in SIZE:
		for c in SIZE:
			var p := piece_at(r, c)
			if p == "": continue
			if piece_color(p) == "r": any_r = true
			elif piece_color(p) == "b": any_b = true
	if not any_r or not any_b:
		game_over = true
		if any_r: winner = "r"
		elif any_b: winner = "b"
		else: winner = "draw"
	return true

func _paths_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i] != b[i]: return false
	return true

# ----------------------------------------------------------------------
# Serialization
# ----------------------------------------------------------------------

func serialize() -> Dictionary:
	var mj_arr := []
	for v in must_jump_from:
		mj_arr.append({"r": v.x, "c": v.y})
	return {
		"board": board.duplicate(true),
		"turn": turn,
		"game_over": game_over,
		"winner": winner,
		"history": move_history.duplicate(true),
		"must_jump_from": mj_arr,
	}

func apply_snapshot(snap: Dictionary) -> void:
	board = snap.get("board", board)
	turn = snap.get("turn", turn)
	game_over = snap.get("game_over", game_over)
	winner = snap.get("winner", winner)
	move_history = snap.get("history", move_history)
	var mj: Array = snap.get("must_jump_from", [])
	must_jump_from = []
	for entry in mj:
		must_jump_from.append(Vector2i(int(entry.get("r", -1)), int(entry.get("c", -1))))
	_refresh_must_jump()