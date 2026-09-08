class_name StylishResultPanel
extends Control

const DESIGN_SIZE := Vector2(656, 830)
const SILVER := Color("e9f3fa")
const QUIET := Color("8795a9")
const DARK := Color("070b12")
const CRIMSON := Color("f05270")
const RANK_LIMITS := [1500, 3500, 6000, 10000, 18000, 30000]
const RANK_NAMES := ["D", "C", "B", "A", "S", "SS", "SSS"]
const RANK_CAPTIONS := ["ЕЩЁ ЕСТЬ КУДА РАСТИ", "ХОРОШЕЕ НАЧАЛО", "УВЕРЕННЫЙ БОЙ", "МОЩНЫЙ РЕЗУЛЬТАТ", "ЧИСТЫЙ СТИЛЬ", "ВЫСШИЙ КЛАСС", "БЕЗУМНЫЙ СТИЛЬ"]
const LETTERS := {
	"S": [[15, 0], [96, 0], [88, 20], [35, 20], [31, 38], [72, 38], [85, 52], [75, 83], [58, 100], [0, 100], [7, 80], [53, 80], [59, 59], [19, 59], [7, 46]],
	"A": [[32, 0], [82, 0], [98, 100], [70, 100], [67, 77], [28, 77], [19, 100], [-6, 100]],
	"B": [[18, 0], [84, 0], [96, 12], [87, 42], [75, 49], [84, 60], [73, 89], [55, 100], [0, 100]],
	"C": [[28, 0], [95, 0], [88, 22], [45, 22], [30, 78], [73, 78], [66, 100], [0, 100], [23, 15]],
	"D": [[18, 0], [80, 0], [97, 22], [77, 80], [55, 100], [0, 100]],
}
const COUNTERS := {
	"A": [[[36, 58], [63, 58], [57, 20], [50, 20]]],
	"B": [[[37, 20], [65, 20], [60, 37], [33, 37]], [[28, 60], [59, 60], [53, 80], [23, 80]]],
	"D": [[[39, 22], [68, 22], [48, 78], [26, 78]]],
}

var score := 0
var rank := "D"
var health := 0
var elapsed := 0.0
var won := true
var duel := false
var final_result := false
var result_heading := ""
var round_scores := {"greg": 0, "mutki": 0}
var totals := {"greg": 0, "mutki": 0}
var _phase := 0.0
var _font: Font
var _heavy: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size.y = 760
	_font = ThemeDB.fallback_font
	_heavy = FontVariation.new()
	_heavy.base_font = _font
	_heavy.variation_embolden = 1.5
	_heavy.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.15, 1), Vector2.ZERO)
	resized.connect(queue_redraw)
	set_process(false)


static func rank_index(value: int) -> int:
	var index := 0
	for limit in RANK_LIMITS:
		if value < limit:
			break
		index += 1
	return index


func present_solo(value: int, health_percent: int, seconds: float, completed: bool) -> void:
	duel = false
	score = maxi(value, 0)
	health = clampi(health_percent, 0, 100)
	elapsed = maxf(seconds, 0.0)
	won = completed
	rank = RANK_NAMES[rank_index(score)]
	_animate()


func present_duel(round_values: Dictionary, total_values: Dictionary, is_final: bool, heading: String) -> void:
	duel = true
	result_heading = heading
	final_result = is_final
	round_scores = round_values.duplicate()
	totals = total_values.duplicate()
	var compared := totals if final_result else round_scores
	score = maxi(int(compared.greg), int(compared.mutki))
	rank = RANK_NAMES[rank_index(score)]
	won = true
	_animate()


func _animate() -> void:
	_phase = 0.0
	set_process(true)
	queue_redraw()


func finish_reveal() -> void:
	_phase = 1.6
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_phase = minf(_phase + delta, 1.6)
	queue_redraw()
	if _phase >= 1.6:
		set_process(false)


func _points(value: int) -> String:
	var digits := str(maxi(0, value))
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += " "
		grouped += digits[index]
	return grouped


func _shown(value: int) -> int:
	var progress := clampf((_phase - 0.18) / 1.05, 0.0, 1.0)
	return roundi(float(value) * (1.0 - pow(1.0 - progress, 3.0)))


func _text(value: String, rect: Rect2, font_size: int, tint: Color = SILVER, bold: bool = false, centered: bool = false) -> void:
	var font: Font = _heavy if bold else _font
	var measured := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if measured.x > rect.size.x - 12:
		font_size = maxi(9, floori(font_size * (rect.size.x - 12) / measured.x))
		measured = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var x := rect.position.x + ((rect.size.x - measured.x) * 0.5 if centered else 6.0)
	var y := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(x + 2, y + 3), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.95))
	draw_string(font, Vector2(x, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


func _cut_rect(rect: Rect2, cut: float = 15) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x, p.y), Vector2(e.x, e.y - cut), e - Vector2(cut, 0), Vector2(p.x, e.y), p + Vector2(0, cut), p + Vector2(cut, 0)])


func _plate(rect: Rect2, accent: Color, prominent: bool = false) -> void:
	var shape := _cut_rect(rect)
	draw_colored_polygon(_cut_rect(Rect2(rect.position + Vector2(0, 7), rect.size)), Color(0, 0, 0, 0.8))
	var colors := PackedColorArray()
	for point in shape:
		var t := (point.y - rect.position.y) / rect.size.y
		colors.append(Color("253344").lerp(Color("0c1019"), t))
	draw_polygon(shape, colors)
	draw_polyline(shape, Color("617586"), 1.1, true)
	draw_line(rect.position + Vector2(18, 1), Vector2(rect.end.x, rect.position.y + 1), Color(accent, 0.9), 2.2, true)
	draw_line(rect.position + Vector2(3, 20), Vector2(rect.position.x + 3, rect.end.y - 4), accent, 3.0, true)
	if prominent:
		for index in 4:
			var p := rect.position + Vector2(22 + index * 12, rect.size.y - 7)
			draw_line(p, p + Vector2(6, -7), Color(accent, 0.65), 3.0, true)


func _glyph_points(points: Array, origin: Vector2, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(origin + Vector2(point[0], point[1]) * height / 100.0)
	return result


func _rank_emblem() -> void:
	var height := 174.0 if rank.length() == 3 else 210.0
	var impact := 1.0 + pow(1.0 - clampf(_phase / 0.35, 0.0, 1.0), 3.0) * 0.16
	height *= impact
	var total_width := height * (1.0 + 0.76 * (rank.length() - 1))
	var origin := Vector2((656 - total_width) * 0.5 + 8, 226 - height * 0.5)
	var accent := MenuVisuals.VIOLET if rank_index(score) >= 4 else MenuVisuals.CYAN
	for index in rank.length():
		var letter := rank[index]
		var glyph_origin := origin + Vector2(index * height * 0.76, 0)
		var points := _glyph_points(LETTERS[letter], glyph_origin, height)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(accent, 0.07), 22, true)
		draw_polyline(outline, Color(accent, 0.16), 11, true)
		for depth in range(8, 0, -2):
			draw_colored_polygon(_glyph_points(LETTERS[letter], glyph_origin + Vector2(depth, depth), height), Color("10131b"))
		var colors := PackedColorArray()
		for point in LETTERS[letter]:
			var y := float(point[1]) / 100.0
			colors.append(Color("f5fbff").lerp(Color("8195a6"), y) if y < 0.52 else Color("566875").lerp(Color("edf3f6"), (y - 0.52) / 0.48))
		draw_polygon(points, colors)
		draw_polyline(outline, SILVER, 1.4, true)
		for counter in COUNTERS.get(letter, []):
			draw_colored_polygon(_glyph_points(counter, glyph_origin, height), DARK)
	_text("РАНГ ЛИДЕРА ПО ОЧКАМ" if duel else "РАНГ СТИЛЯ", Rect2(32, 77, 592, 28), 16, QUIET, false, true)
	_text(RANK_CAPTIONS[rank_index(score)], Rect2(32, 341, 592, 30), 19, accent, true, true)


func _draw() -> void:
	if _font == null or size.x <= 0 or size.y <= 0:
		return
	draw_set_transform(Vector2.ZERO, 0, size / DESIGN_SIZE)
	var outline := _cut_rect(Rect2(2, 2, 652, 824), 28)
	draw_colored_polygon(outline, Color(0.025, 0.04, 0.065, 0.96))
	draw_polyline(outline, Color("394554"), 1.5, true)
	# Split metal trim and diagonal cuts carry the styling even with a zero score.
	draw_line(Vector2(28, 3), Vector2(330, 3), MenuVisuals.CYAN, 3, true)
	draw_line(Vector2(330, 3), Vector2(654, 3), MenuVisuals.VIOLET, 3, true)
	for index in 5:
		var left := Vector2(8, 115 + index * 27)
		draw_line(left, left + Vector2(29, -20), Color(CRIMSON, 0.50 - index * 0.06), 3, true)
		draw_line(Vector2(619, 286 + index * 18), Vector2(647, 266 + index * 18), Color(MenuVisuals.VIOLET, 0.35), 2, true)
	for index in 24:
		var angle := deg_to_rad(float(index * 15 - 32))
		var p := Vector2(328, 225) + Vector2(cos(angle) * 185, sin(angle) * 126)
		draw_line(p, p + Vector2(16, -5), Color("253343"), 1, true)
	_rank_emblem()
	if duel:
		_draw_duel()
	else:
		_draw_solo()
	var flash := maxf(0.0, 1.0 - _phase / 0.48)
	if flash > 0:
		draw_line(Vector2(8, 375 - 44 * flash), Vector2(648, 330 - 44 * flash), Color(SILVER, flash * 0.6), 2 + 7 * flash, true)
	draw_set_transform(Vector2.ZERO)


func _draw_solo() -> void:
	_text("МИССИЯ 01 ПРОЙДЕНА" if won else "МИССИЯ НЕ ПРОЙДЕНА", Rect2(30, 24, 596, 46), 29, SILVER if won else CRIMSON, true, true)
	_plate(Rect2(26, 389, 604, 160), MenuVisuals.CYAN, true)
	_text("ОБЩИЙ СЧЁТ", Rect2(45, 400, 560, 30), 17, QUIET, false, true)
	_text(_points(_shown(score)), Rect2(42, 438, 572, 95), 88, SILVER, true, true)
	_plate(Rect2(26, 575, 292, 97), MenuVisuals.CYAN)
	_plate(Rect2(338, 575, 292, 97), MenuVisuals.VIOLET)
	_text("ВРЕМЯ", Rect2(46, 586, 250, 26), 16, QUIET)
	_text("%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Rect2(46, 614, 250, 46), 34, SILVER, true)
	_text("ЗДОРОВЬЕ", Rect2(358, 586, 250, 26), 16, QUIET)
	_text("%d%%" % health, Rect2(358, 614, 250, 46), 34, SILVER, true)
	var challenge := won and health >= 50
	var tint := Color("83e4c3") if challenge else CRIMSON
	draw_line(Vector2(40, 717), Vector2(615, 717), Color(tint, 0.35), 1, true)
	_text("ИСПЫТАНИЕ ВЫПОЛНЕНО" if challenge else ("ИСПЫТАНИЕ · СОХРАНИ 50% ЗДОРОВЬЯ" if won else "РОЯЛТИ ЕЩЁ МОЖНО ВЕРНУТЬ"), Rect2(30, 731, 596, 32), 19, tint, true, true)
	_text("Погоня за Капелой продолжается." if won else "Новая попытка. Новый шанс показать стиль.", Rect2(30, 773, 596, 28), 17, QUIET, false, true)


func _draw_duel() -> void:
	_text(result_heading, Rect2(30, 24, 596, 46), 30, SILVER, true, true)
	var compared := totals if final_result else round_scores
	var equal := int(compared.greg) == int(compared.mutki)
	var leader := "ГРИША" if int(compared.greg) > int(compared.mutki) else "МУТКИ"
	var tint := MenuVisuals.CYAN if leader == "ГРИША" else MenuVisuals.VIOLET
	_text("НА РАВНЫХ · НИЧЬЯ" if equal else (("ПОБЕДИТЕЛЬ · " if final_result else "ЛУЧШИЙ В РАУНДЕ · ") + leader), Rect2(28, 382, 600, 30), 21, SILVER if equal else tint, true, true)
	for index in 2:
		var hero := "greg" if index == 0 else "mutki"
		var name_text := "ГРИША" if index == 0 else "МУТКИ"
		var accent := MenuVisuals.CYAN if index == 0 else MenuVisuals.VIOLET
		var y := 434.0 + index * 184
		_plate(Rect2(26, y, 604, 164), accent, true)
		_text(name_text, Rect2(47, y + 12, 250, 30), 23, accent, true)
		_text("ВСЕГО" if final_result else "ЗА РАУНД", Rect2(420, y + 12, 184, 30), 16, QUIET, false, true)
		_text(_points(_shown(int(compared[hero]))), Rect2(44, y + 48, 560, 66), 60, SILVER, true, true)
		var detail := "За раунд  +" + _points(int(round_scores[hero])) if final_result else "Всего  " + _points(int(totals[hero]))
		_text(detail, Rect2(50, y + 127, 554, 24), 17, QUIET, false, true)
