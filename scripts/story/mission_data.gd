class_name MissionData
extends RefCounted

const TITLE := "ПОГОНЯ ЗА РОЯЛТИ"
const WAVE_COUNT := 3
const INTRO_VIDEO := "res://assets/videos/story/mission_01_intro.ogv"
const CANONICAL_ART := "res://assets/style/characters_canonical.png"
const TITLE_ART := "res://assets/style/urban_title.png"
const OUTRO := [
	{
		"chapter": "ПРОХОД ОТКРЫТ",
		"title": "Погоня продолжается",
		"speaker": "ГРИША И МУТКИ",
		"text": "Хулиганы больше не преграждают путь. Гриша и Мутки продолжают погоню за Капелой и его мехом — роялти ещё предстоит вернуть.",
		"art": TITLE_ART,
	},
]
const OBJECTIVES := ["Расчисти вход во двор", "Удержи обе стороны", "Открой дальний проход"]

static func objective(wave_number: int) -> String:
	return OBJECTIVES[clampi(wave_number - 1, 0, OBJECTIVES.size() - 1)]
