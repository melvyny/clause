extends RefCounted
## Goldmend :: icon set, authored as inline SVG and rasterised at runtime.
## Every icon is an ivory glyph; tex() can wrap it in a coloured "porcelain
## seal" disc with a gold rim, so the whole UI shares one visual language.
## To replace art later, swap the SVG strings (or load files) here only.

const INK := "#231c35"
const IVORY := "#f6f1e4"

static var _cache := {}

## glyph bodies drawn in a 64x64 box. Use {F} for the glyph fill, {D} for dark details.
const GLYPHS := {
	# elements
	"fire": "<path fill='{F}' d='M32 5C40 19 51 26 48 41C46 53 38 59 32 59C24 59 15 53 16 40C17 30 24 26 26 15C30 23 33 25 32 5Z'/><path fill='{D}' opacity='.35' d='M32 32C36 38 40 42 38 48C37 53 34 55 32 55C28 55 25 52 26 46C27 41 31 39 32 32Z'/>",
	"water": "<path fill='{F}' d='M32 5C42 21 50 31 50 42A18 18 0 0 1 14 42C14 31 22 21 32 5Z'/><path fill='none' stroke='{D}' stroke-opacity='.35' stroke-width='4' stroke-linecap='round' d='M22 42A10 10 0 0 0 30 51'/>",
	"wind": "<g fill='none' stroke='{F}' stroke-width='6' stroke-linecap='round'><path d='M6 22H38A8 8 0 1 0 30 14'/><path d='M6 34H48A8 8 0 1 1 40 42'/><path d='M6 46H28'/></g>",
	"light": "<circle cx='32' cy='32' r='11' fill='{F}'/><g stroke='{F}' stroke-width='5' stroke-linecap='round'><path d='M32 6V14M32 50V58M6 32H14M50 32H58M13 13L19 19M45 45L51 51M13 51L19 45M45 19L51 13'/></g>",
	"dark": "<path fill='{F}' d='M40 6A26 26 0 1 0 58 44A19 19 0 1 1 40 6Z'/><circle cx='48' cy='16' r='3' fill='{F}'/>",
	# statuses
	"atk_up": "<path fill='{F}' d='M46 6H58V18L30 46L18 34Z'/><path fill='{F}' d='M14 38L26 50L20 56L8 44Z'/><path fill='{D}' opacity='.4' d='M50 10L54 10L54 14L30 38L26 34Z'/><path fill='{F}' d='M10 16L20 6L30 16H24V26H16V16Z'/>",
	"def_up": "<path fill='{F}' d='M32 5L55 13V30C55 45 45 55 32 59C19 55 9 45 9 30V13Z'/><path fill='{D}' d='M32 20L44 34H37V44H27V34H20Z'/>",
	"immunity": "<path fill='{F}' d='M32 5L55 13V30C55 45 45 55 32 59C19 55 9 45 9 30V13Z'/><path fill='{D}' d='M32 18L35 28L45 29L37 35L40 45L32 39L24 45L27 35L19 29L29 28Z'/>",
	"def_break": "<path fill='{F}' d='M30 5L9 13V30C9 45 19 55 30 59L26 42L32 30L26 20Z'/><path fill='{F}' d='M36 7L55 14V30C55 45 46 54 36 58L40 42L35 30L40 21Z'/>",
	"dot": "<path fill='{F}' d='M32 5C40 19 51 26 48 41C46 53 38 59 32 59C24 59 15 53 16 40C17 30 24 26 26 15C30 23 33 25 32 5Z'/><circle cx='32' cy='44' r='6' fill='{D}' opacity='.5'/>",
	"stun": "<g fill='{F}'><path d='M20 10L23 19L32 20L25 26L27 35L20 30L13 35L15 26L8 20L17 19Z'/><path d='M44 20L47 29L56 30L49 36L51 45L44 40L37 45L39 36L32 30L41 29Z'/></g><ellipse cx='32' cy='52' rx='20' ry='5' fill='none' stroke='{F}' stroke-width='4'/>",
	"freeze": "<g stroke='{F}' stroke-width='5' stroke-linecap='round' fill='none'><path d='M32 6V58M9 19L55 45M9 45L55 19'/><path d='M26 10L32 16L38 10M26 54L32 48L38 54M10 27L18 25L16 17M48 47L46 39L54 37M10 37L18 39L16 47M48 17L46 25L54 27'/></g>",
	# skill kinds
	"strike": "<g fill='{F}'><path d='M14 52L44 8L50 12L22 56Z'/><path d='M26 56L52 20L57 25L33 58Z'/><path d='M8 44L32 6L37 9L15 48Z'/></g>",
	"orb": "<circle cx='40' cy='24' r='14' fill='{F}'/><g stroke='{F}' stroke-width='5' stroke-linecap='round' opacity='.7'><path d='M8 56L24 40M16 58L28 46M6 46L20 34'/></g>",
	"burst": "<path fill='{F}' d='M32 4L37 22L54 12L44 29L60 34L42 39L50 56L34 45L28 60L24 43L8 50L18 35L4 28L22 25L14 9L29 20Z'/>",
	"heal": "<path fill='{F}' d='M24 8H40V24H56V40H40V56H24V40H8V24H24Z'/>",
	"buff": "<g fill='{F}'><path d='M32 6L54 28H42L32 18L22 28H10Z'/><path d='M32 28L54 50H42L32 40L22 50H10Z'/></g>",
	"ult": "<path fill='{F}' d='M32 3L38 22L58 16L44 31L60 44L40 42L38 62L32 46L26 62L24 42L4 44L20 31L6 16L26 22Z'/><circle cx='32' cy='32' r='7' fill='{D}' opacity='.35'/>",
	# ui
	"auto": "<g fill='none' stroke='{F}' stroke-width='6' stroke-linecap='round'><path d='M50 26A19 19 0 0 0 16 20'/><path d='M14 38A19 19 0 0 0 48 44'/></g><path fill='{F}' d='M8 12L22 12L14 26Z'/><path fill='{F}' d='M56 52L42 52L50 38Z'/>",
	"speed": "<g fill='{F}'><path d='M8 12L32 32L8 52Z'/><path d='M32 12L56 32L32 52Z'/></g>",
	"book": "<path fill='{F}' d='M6 12C16 8 26 10 31 16V56C26 50 16 48 6 52Z'/><path fill='{F}' d='M58 12C48 8 38 10 33 16V56C38 50 48 48 58 52Z'/>",
	"gear": "<path fill='{F}' d='M28 4H36L38 12L45 15L52 10L57 16L52 23L55 30L63 32V36L55 38L52 45L57 52L51 58L44 53L37 56L36 63H28L27 56L20 53L13 58L7 52L12 45L9 38L1 36V30L9 28L12 21L7 14L13 9L20 13L27 10Z'/><circle cx='32' cy='33' r='10' fill='{D}'/>",
	"scroll": "<rect x='12' y='8' width='40' height='48' rx='6' fill='{F}'/><g stroke='{D}' stroke-width='4' stroke-linecap='round'><path d='M20 20H44M20 30H44M20 40H36'/></g>",
	"shard": "<path fill='{F}' d='M32 4L50 20L44 50L24 60L12 34Z'/><path fill='{D}' opacity='.3' d='M32 4L36 30L24 60L12 34Z'/>",
	"crown": "<path fill='{F}' d='M8 48L12 16L24 32L32 10L40 32L52 16L56 48Z'/><rect x='8' y='50' width='48' height='6' fill='{F}'/>",
	"seam": "<path fill='none' stroke='{F}' stroke-width='7' stroke-linecap='round' stroke-linejoin='round' d='M10 12L26 26L20 38L38 46L52 58'/>",
	"gold": "<circle cx='32' cy='32' r='24' fill='{F}'/><circle cx='32' cy='32' r='16' fill='none' stroke='{D}' stroke-opacity='.35' stroke-width='4'/><rect x='27' y='27' width='10' height='10' fill='{D}' opacity='.35'/>",
	"ring": "<circle cx='32' cy='32' r='28' fill='none' stroke='{F}' stroke-width='6'/>",
	# vessel spirit silhouettes (portraits)
	"chickencup": "<path fill='{F}' d='M10 32H54L46 50H18Z'/><rect x='24' y='50' width='16' height='6' fill='{F}'/><circle cx='34' cy='20' r='9' fill='{F}'/><path fill='{F}' d='M42 18L52 22L42 25Z'/><g fill='{F}'><circle cx='30' cy='9' r='3.5'/><circle cx='35' cy='8' r='3.5'/></g><path fill='{F}' d='M14 30L8 12L20 28Z'/><circle cx='36' cy='18' r='2' fill='{D}'/><path fill='none' stroke='{D}' stroke-opacity='.4' stroke-width='3' d='M16 40H48'/>",
	"rulotus": "<path fill='{F}' d='M6 28Q12 21 18 28Q25 21 32 28Q39 21 46 28Q52 21 58 28L48 50H16Z'/><rect x='24' y='50' width='16' height='6' fill='{F}'/><path fill='{F}' d='M32 8C38 14 38 22 32 26C26 22 26 14 32 8Z'/><g fill='{D}'><circle cx='25' cy='38' r='2.5'/><circle cx='39' cy='38' r='2.5'/></g>",
	"sancaihorse": "<path fill='{F}' d='M10 32Q12 24 22 24H40L46 10L56 12L58 20L50 24L48 36Q46 40 42 40V56H37V42H22V56H17V40Q10 38 10 32Z'/><path fill='{D}' opacity='.35' d='M20 24H36V30H20Z'/><circle cx='52' cy='15' r='2' fill='{D}'/>",
	"childpillow": "<rect x='8' y='46' width='48' height='10' rx='5' fill='{F}'/><ellipse cx='38' cy='38' rx='18' ry='9' fill='{F}'/><circle cx='18' cy='30' r='12' fill='{F}'/><path fill='none' stroke='{D}' stroke-width='2.5' stroke-linecap='round' d='M12 30Q14 32 16 30M20 30Q22 32 24 30'/><path fill='{F}' d='M50 32L58 22L60 26L54 34Z'/>",
	"tigerpillow": "<rect x='14' y='24' width='44' height='24' rx='12' fill='{F}'/><circle cx='16' cy='34' r='12' fill='{F}'/><path fill='{F}' d='M6 24L10 14L16 22ZM20 22L26 14L28 24Z'/><g stroke='{D}' stroke-width='3' stroke-linecap='round' opacity='.55'><path d='M32 26V36M40 26V38M48 26V36'/></g><g fill='{D}'><circle cx='12' cy='32' r='2'/><circle cx='20' cy='32' r='2'/></g>",
	"generaljar": "<path fill='{F}' d='M22 16H42V19C55 25 55 43 45 54H19C9 43 9 25 22 19Z'/><path fill='{F}' d='M18 16Q32 2 46 16Z'/><circle cx='32' cy='6' r='3.5' fill='{F}'/><g fill='{D}'><circle cx='26' cy='30' r='2.5'/><circle cx='38' cy='30' r='2.5'/></g><path fill='none' stroke='{D}' stroke-width='3' stroke-linecap='round' d='M24 38Q28 35 32 38Q36 35 40 38'/>",
	"phoenixvase": "<path fill='{F}' d='M28 4H36V22C44 26 47 34 47 56H17C17 34 20 26 28 22Z'/><path fill='{F}' d='M28 14Q18 10 16 16Q18 20 26 18ZM36 14Q46 10 48 16Q46 20 38 18Z'/><g fill='{D}'><circle cx='27' cy='38' r='2.2'/><circle cx='37' cy='38' r='2.2'/></g>",
	"yohenbowl": "<path fill='{F}' d='M6 20H58L44 48H20Z'/><rect x='24' y='48' width='16' height='6' fill='{F}'/><g fill='{D}' opacity='.6'><circle cx='20' cy='26' r='2.5'/><circle cx='30' cy='31' r='2'/><circle cx='42' cy='26' r='3'/><circle cx='36' cy='38' r='2'/><circle cx='26' cy='40' r='1.8'/></g>",
	"boss": "<path fill='{F}' d='M22 12H42V16C56 24 56 44 46 56H18C8 44 8 24 22 16Z'/><path fill='none' stroke='{D}' stroke-width='3.5' stroke-linejoin='round' d='M30 12L26 26L36 32L28 44L34 56'/><g fill='{D}'><circle cx='24' cy='30' r='3'/><circle cx='40' cy='30' r='3'/></g>",
}

const STATUS_ICON := {"atk_up": "atk_up", "def_up": "def_up", "immunity": "immunity", "def_break": "def_break", "dot": "dot", "stun": "stun", "freeze": "freeze"}
const ELEMENT_ICON := ["fire", "water", "wind", "light", "dark"]


## Rasterised icon. With `bg` set, the glyph sits on a glazed disc with a gold rim.
static func tex(icon_name: String, bg: Color = Color(0, 0, 0, 0), size: int = 64, fg: String = IVORY) -> Texture2D:
	var key := "%s|%s|%d|%s" % [icon_name, bg.to_html(), size, fg]
	if _cache.has(key):
		return _cache[key]
	var body: String = GLYPHS.get(icon_name, GLYPHS["shard"])
	body = body.replace("{F}", fg).replace("{D}", INK)
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>"
	if bg.a > 0.0:
		svg += "<circle cx='32' cy='32' r='30' fill='#%s' stroke='#e2b35c' stroke-width='3'/>" % bg.to_html(false)
		svg += "<g transform='translate(12 12) scale(0.625)'>%s</g>" % body
	else:
		svg += body
	svg += "</svg>"
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(size) / 64.0)
	var t: Texture2D
	if err == OK:
		t = ImageTexture.create_from_image(img)
	else:
		t = PlaceholderTexture2D.new()
	_cache[key] = t
	return t


static func element(e: int, size: int = 64, disc: bool = true) -> Texture2D:
	const COLORS := ["b8452c", "2f78b8", "3f9a6a", "c9a13f", "6b3fa8"]
	return tex(ELEMENT_ICON[e], Color.html(COLORS[e]) if disc else Color(0, 0, 0, 0), size)


static func status(id: String, color: Color, size: int = 40) -> Texture2D:
	return tex(STATUS_ICON.get(id, "shard"), color.darkened(0.35), size)


## Icon representing a skill's shape: ultimate, heal, team buff, AoE, melee, ranged.
static func skill_kind(sk: Dictionary, index: int) -> String:
	if index == 2:
		return "ult"
	var heals := false
	for eff in sk.effects:
		if eff.type == "heal_allies":
			heals = true
	if heals:
		return "heal"
	if sk.target == "all_allies":
		return "buff"
	if sk.target == "all_enemies":
		return "burst"
	return "strike" if sk.anim == "melee" else "orb"


static func portrait(species_id: String, element_index: int, size: int = 64) -> Texture2D:
	const COLORS := ["b8452c", "2f78b8", "3f9a6a", "c9a13f", "6b3fa8"]
	return tex(species_id if GLYPHS.has(species_id) else "shard", Color.html(COLORS[element_index]), size)
