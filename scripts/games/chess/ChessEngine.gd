extends RefCounted
## Pure chess engine. Server-authoritative.
## Pieces: K Q R B N P (white) / k q r b n p (black) / "" empty.

class_name ChessEngine

const SIZE := 8

var board: Array = []
var turn: String = "white"
var castling: Dictionary = {"white_king": true, "white_queen": true, "black_king": true, "black_queen": true}
var en_passant: Vector2i = Vector2i(-1, -1)
var halfmove_clock: int = 0
var fullmove_number: int = 1
var history: Array = []
var game_over: bool = false
var winner: String = ""

func _init() -> void: reset()

func reset() -> void:
	board = []
	for r in SIZE:
		var row = []
		for c in SIZE: row.append("")
		board.append(row)
	board[7][0] = "R"; board[7][1] = "N"; board[7][2] = "B"; board[7][3] = "Q"
	board[7][4] = "K"; board[7][5] = "B"; board[7][6] = "N"; board[7][7] = "R"
	for c in SIZE: board[6][c] = "P"
	board[0][0] = "r"; board[0][1] = "n"; board[0][2] = "b"; board[0][3] = "q"
	board[0][4] = "k"; board[0][5] = "b"; board[0][6] = "n"; board[0][7] = "r"
	for c in SIZE: board[1][c] = "p"
	turn = "white"
	castling = {"white_king": true, "white_queen": true, "black_king": true, "black_queen": true}
	en_passant = Vector2i(-1, -1)
	halfmove_clock = 0
	fullmove_number = 1
	history = []
	game_over = false
	winner = ""

func piece_at(r: int, c: int) -> String:
	if r < 0 or r >= SIZE or c < 0 or c >= SIZE: return ""
	return board[r][c]

func is_white(p: String) -> bool: return p != "" and p == p.to_upper()
func is_black(p: String) -> bool: return p != "" and p == p.to_lower()
func piece_color(p: String) -> String:
	if p == "": return ""
	return "white" if is_white(p) else "black"
func piece_type(p: String) -> String: return p.to_lower()

func pseudo_legal_moves(r: int, c: int) -> Array:
	var piece = piece_at(r, c)
	if piece == "": return []
	var color = piece_color(piece)
	var t = piece_type(piece)
	var moves: Array = []
	match t:
		"p": moves = _pawn_moves(r, c, color)
		"n": moves = _knight_moves(r, c, color)
		"b": moves = _slider_moves(r, c, color, [[-1,-1],[-1,1],[1,-1],[1,1]])
		"r": moves = _slider_moves(r, c, color, [[-1,0],[1,0],[0,-1],[0,1]])
		"q": moves = _slider_moves(r, c, color, [[-1,-1],[-1,1],[1,-1],[1,1],[-1,0],[1,0],[0,-1],[0,1]])
		"k": moves = _king_moves(r, c, color)
	return moves

func _pawn_moves(r: int, c: int, color: String) -> Array:
	var moves: Array = []
	var dir := -1 if color == "white" else 1
	var start_row := 6 if color == "white" else 1
	var promo_row := 0 if color == "white" else 7
	var nr := r + dir
	if nr >= 0 and nr < SIZE and piece_at(nr, c) == "":
		if nr == promo_row: moves.append_array([Vector2i(nr,c), Vector2i(nr,c), Vector2i(nr,c), Vector2i(nr,c)])
		else: moves.append(Vector2i(nr, c))
		if r == start_row:
			var nr2 := r + 2*dir
			if piece_at(nr2, c) == "": moves.append(Vector2i(nr2, c))
	for dc in [-1, 1]:
		var nc: int = c + int(dc)
		if nc < 0 or nc >= SIZE: continue
		var nr2: int = r + dir
		if nr2 < 0 or nr2 >= SIZE: continue
		var target: String = piece_at(nr2, nc)
		if target != "" and piece_color(target) != color:
			if nr2 == promo_row: moves.append_array([Vector2i(nr2,nc), Vector2i(nr2,nc), Vector2i(nr2,nc), Vector2i(nr2,nc)])
			else: moves.append(Vector2i(nr2, nc))
		if Vector2i(nr2, nc) == en_passant: moves.append(Vector2i(nr2, nc))
	return moves

func _knight_moves(r: int, c: int, color: String) -> Array:
	var moves: Array = []
	for d in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]:
		var nr: int = r + int(d[0]); var nc: int = c + int(d[1])
		if nr < 0 or nr >= SIZE or nc < 0 or nc >= SIZE: continue
		var t: String = piece_at(nr, nc)
		if t == "" or piece_color(t) != color: moves.append(Vector2i(nr, nc))
	return moves

func _slider_moves(r: int, c: int, color: String, dirs: Array) -> Array:
	var moves: Array = []
	for d in dirs:
		var nr: int = r + int(d[0]); var nc: int = c + int(d[1])
		while nr >= 0 and nr < SIZE and nc >= 0 and nc < SIZE:
			var t: String = piece_at(nr, nc)
			if t == "": moves.append(Vector2i(nr, nc))
			else:
				if piece_color(t) != color: moves.append(Vector2i(nr, nc))
				break
			nr += int(d[0]); nc += int(d[1])
	return moves

func _king_moves(r: int, c: int, color: String) -> Array:
	var moves: Array = []
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if int(dr) == 0 and int(dc) == 0: continue
			var nr: int = r + int(dr); var nc: int = c + int(dc)
			if nr < 0 or nr >= SIZE or nc < 0 or nc >= SIZE: continue
			var t: String = piece_at(nr, nc)
			if t == "" or piece_color(t) != color: moves.append(Vector2i(nr, nc))
	if not is_in_check(color):
		var row := 7 if color == "white" else 0
		if castling.get(color + "_king", false):
			if piece_at(row, 5) == "" and piece_at(row, 6) == "":
				if not _square_attacked(row, 5, "black" if color == "white" else "white") and not _square_attacked(row, 6, "black" if color == "white" else "white"): moves.append(Vector2i(row, 6))
		if castling.get(color + "_queen", false):
			if piece_at(row, 1) == "" and piece_at(row, 2) == "" and piece_at(row, 3) == "":
				if not _square_attacked(row, 3, "black" if color == "white" else "white") and not _square_attacked(row, 2, "black" if color == "white" else "white"): moves.append(Vector2i(row, 2))
	return moves

func _square_attacked(r: int, c: int, by_color: String) -> bool:
	for rr in SIZE:
		for cc in SIZE:
			var p := piece_at(rr, cc)
			if p == "" or piece_color(p) != by_color: continue
			var t := piece_type(p)
			match t:
				"p":
					var dir := -1 if by_color == "white" else 1
					if rr + dir == r and (cc - 1 == c or cc + 1 == c): return true
				"n":
					for d in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]:
						if rr + d[0] == r and cc + d[1] == c: return true
				"b","r","q":
					var dirs: Array = []
					if t in ["b","q"]: dirs += [[-1,-1],[-1,1],[1,-1],[1,1]]
					if t in ["r","q"]: dirs += [[-1,0],[1,0],[0,-1],[0,1]]
					for d in dirs:
						var nr: int = rr + int(d[0]); var nc: int = cc + int(d[1])
						while nr >= 0 and nr < SIZE and nc >= 0 and nc < SIZE:
							if nr == r and nc == c: return true
							if piece_at(nr, nc) != "": break
						nr += int(d[0]); nc += int(d[1])
			"k":
				for dr in [-1,0,1]:
					for dc in [-1,0,1]:
						if int(dr)==0 and int(dc)==0: continue
						if rr+int(dr)==r and cc+int(dc)==c: return true
	return false

func is_in_check(color: String) -> bool:
	var king := "K" if color == "white" else "k"
	var kr := -1; var kc := -1
	for r in SIZE:
		for c in SIZE:
			if piece_at(r, c) == king: kr = r; kc = c; break
		if kr != -1: break
	if kr == -1: return false
	var enemy := "black" if color == "white" else "white"
	return _square_attacked(kr, kc, enemy)

func legal_moves_from(r: int, c: int) -> Array:
	var color = piece_color(piece_at(r, c))
	if color != turn: return []
	var result: Array = []
	for m in pseudo_legal_moves(r, c):
		if piece_type(piece_at(r, c)) == "k" and abs(int(m.x) - c) == 2:
			var step_col: int = (int(m.x) + c) / 2
			if is_in_check(color) or _square_attacked(r, step_col, "black" if color == "white" else "white"): continue
		if _move_legal(r, c, m): result.append(m)
	return result

func has_any_legal_move(color: String) -> bool:
	for r in SIZE:
		for c in SIZE:
			if piece_color(piece_at(r, c)) != color: continue
			var saved_turn := turn; turn = color
			var moves := legal_moves_from(r, c)
			turn = saved_turn
			if not moves.is_empty(): return true
	return false

func _move_legal(from_r: int, from_c: int, to: Vector2i) -> bool:
	var piece := piece_at(from_r, from_c)
	var captured := piece_at(to.x, to.y)
	var ep_captured := ""
	if piece_type(piece) == "p" and to == en_passant:
		ep_captured = piece_at(from_r, to.y)
		board[from_r][to.y] = ""
	board[from_r][from_c] = ""
	board[to.x][to.y] = piece
	var color := piece_color(piece)
	var in_check := is_in_check(color)
	board[from_r][from_c] = piece
	board[to.x][to.y] = captured
	if ep_captured != "": board[from_r][to.y] = ep_captured
	return not in_check

func apply_move(from_r: int, from_c: int, to_r: int, to_c: int, promotion: String = "Q") -> bool:
	if game_over: return false
	var piece := piece_at(from_r, from_c)
	if piece == "" or piece_color(piece) != turn: return false
	var legal := legal_moves_from(from_r, from_c)
	var is_promotion_move := piece_type(piece) == "p" and (to_r == 0 or to_r == SIZE-1)
	var target := Vector2i(to_r, to_c)
	if not legal.has(target):
		if is_promotion_move:
			var base_legal := legal.duplicate()
			var seen = {}; var filtered: Array = []
			for m in base_legal:
				if not seen.has(m): seen[m] = true; filtered.append(m)
			if not filtered.has(target): return false
		else: return false
	var captured := piece_at(to_r, to_c)
	var ep_captured_piece := ""
	var ep_captured_pos := Vector2i(-1, -1)
	if piece_type(piece) == "p" and target == en_passant:
		ep_captured_piece = piece_at(from_r, to_c)
		ep_captured_pos = Vector2i(from_r, to_c)
		board[from_r][to_c] = ""
	board[from_r][from_c] = ""
	board[to_r][to_c] = piece
	if piece_type(piece) == "k" and abs(to_c - from_c) == 2:
		var row := from_r
		if to_c == 6: board[row][5] = board[row][7]; board[row][7] = ""
		elif to_c == 2: board[row][3] = board[row][0]; board[row][0] = ""
	if is_promotion_move:
		var promo_piece := promotion.to_upper() if piece_color(piece) == "white" else promotion.to_lower()
		board[to_r][to_c] = promo_piece
	if piece == "K": castling["white_king"] = false; castling["white_queen"] = false
	elif piece == "k": castling["black_king"] = false; castling["black_queen"] = false
	elif piece == "R" and from_r == 7 and from_c == 0: castling["white_queen"] = false
	elif piece == "R" and from_r == 7 and from_c == 7: castling["white_king"] = false
	elif piece == "r" and from_r == 0 and from_c == 0: castling["black_queen"] = false
	elif piece == "r" and from_r == 0 and from_c == 7: castling["black_king"] = false
	if to_r == 0 and to_c == 0: castling["black_queen"] = false
	if to_r == 0 and to_c == 7: castling["black_king"] = false
	if to_r == 7 and to_c == 0: castling["white_queen"] = false
	if to_r == 7 and to_c == 7: castling["white_king"] = false
	en_passant = Vector2i(-1, -1)
	if piece_type(piece) == "p" and abs(to_r - from_r) == 2: en_passant = Vector2i((to_r + from_r)/2, from_c)
	if piece_type(piece) == "p" or captured != "" or ep_captured_piece != "": halfmove_clock = 0
	else: halfmove_clock += 1
	if turn == "black": fullmove_number += 1
	turn = "black" if turn == "white" else "white"
	history.append(_algebraic(from_r, from_c, to_r, to_c, captured, is_promotion_move, promotion))
	var enemy := turn
	if is_in_check(enemy):
		if not has_any_legal_move(enemy): game_over = true; winner = "white" if enemy == "black" else "black"
	elif not has_any_legal_move(enemy): game_over = true; winner = "draw"
	elif halfmove_clock >= 100: game_over = true; winner = "draw"
	return true

func _algebraic(fr: int, fc: int, tr: int, tc: int, captured: String, is_promo: bool, promo: String) -> String:
	var files := "abcdefgh"
	var piece := piece_at(tr, tc)
	var letter := ""
	match piece_type(piece):
		"": letter = ""
		"n": letter = "N"; "b": letter = "B"; "r": letter = "R"; "q": letter = "Q"; "k": letter = "K"; "p": letter = ""
	var from_sq := "%s%d" % [files[fc], SIZE - fr]
	var to_sq := "%s%d" % [files[tc], SIZE - tr]
	var suffix := ""
	if is_promo: suffix = "=%s" % promo.to_upper()
	return "%s%s%s%s%s" % [letter, from_sq, "x" if captured != "" else "-", to_sq, suffix]

func serialize() -> Dictionary:
	return {"board": board.duplicate(true), "turn": turn, "castling": castling.duplicate(), "en_passant": [en_passant.x, en_passant.y], "history": history.duplicate(), "game_over": game_over, "winner": winner}

func apply_snapshot(snap: Dictionary) -> void:
	board = snap.get("board", board)
	turn = snap.get("turn", turn)
	castling = snap.get("castling", castling)
	var ep: Array = snap.get("en_passant", [-1, -1])
	en_passant = Vector2i(ep[0], ep[1])
	history = snap.get("history", history)
	game_over = snap.get("game_over", game_over)
	winner = snap.get("winner", winner)