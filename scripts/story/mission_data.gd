class_name MissionData
extends RefCounted

const TITLE := "ПОГОНЯ ЗА РОЯЛТИ"
const WAVE_COUNT := 3
const CANONICAL_ART := "res://assets/style/characters_canonical.png"
const TITLE_ART := "res://assets/style/urban_title.png"
const BANK_ART := "res://assets/story/bank_01_walk.png"
const EXPLOSION_ART := "res://assets/story/bank_02_explosion.png"
const MECH_ART := "res://assets/story/bank_03_mech_theft.png"
const BRIBE_ART := "res://assets/story/bank_04_bribe.png"
const AMBUSH_ART := "res://assets/story/bank_05_ambush.png"
const INTRO := [
	{
		"chapter": "ЭКСПЕДИЦИЯ · МИССИЯ 01",
		"title": "За роялти!",
		"speaker": "ГРИША И МУТКИ",
		"text": "Гриша и Мутки радостно идут в банк за роялти. Ещё немного — и можно забрать свои деньги!",
		"art": BANK_ART,
	},
	{
		"chapter": "У ВХОДА В БАНК",
		"title": "Взрыв!",
		"speaker": "ГРИША И МУТКИ",
		"text": "Но едва друзья подошли к банку, прогремел взрыв! Из дыма показались огромные металлические щупальца.",
		"art": EXPLOSION_ART,
	},
	{
		"chapter": "ОГРАБЛЕНИЕ",
		"title": "Это Капела!",
		"speaker": "ДОКТОР КАПЕЛА",
		"text": "Доктор Капела управляет огромным мехом со щупальцами. Он опустошил хранилище и забрал все роялти! Друзья бросаются в погоню.",
		"art": MECH_ART,
	},
	{
		"chapter": "СДЕЛКА ВО ДВОРЕ",
		"title": "Платная помеха",
		"speaker": "ДОКТОР КАПЕЛА",
		"text": "Чтобы оторваться от погони, Капела платит местным хулиганам: задержите этих двоих! Мех уходит дальше с украденными роялти.",
		"art": BRIBE_ART,
	},
	{
		"chapter": "МИССИЯ 01 · ЗАСАДА",
		"title": "Прорвись за Капелой",
		"speaker": "ПЛАН МИССИИ",
		"text": "Хулиганы перекрыли путь. Победи три волны и продолжи погоню. Тап слева или справа — удар. A / D — поворот, пробел — удар.",
		"art": AMBUSH_ART,
	},
]
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
