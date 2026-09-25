extends PanelContainer
## Goldmend :: shared hover tooltip (rich text, follows the mouse, stays on screen).
## Usage: var tip := Tip.new(); some_control.add_child(tip); tip.attach(button, func(): return "text")

const M = preload("po_mat.gd")

var _text: RichTextLabel
var _owner: Object = null


func _init() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.09, 0.96)
	sb.border_color = Color(0.9, 0.7, 0.38)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(340, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("normal_font", M.ui_font())
	_text.add_theme_font_override("bold_font", M.ui_font())
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	add_child(_text)
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_place()


## Shows `text` near the mouse. `owner` lets a caller hide only its own tip.
func show_text(text: String, owner: Object = null) -> void:
	if text == "":
		hide_for(owner)
		return
	_owner = owner
	_text.text = text
	visible = true
	reset_size()
	_place()


func hide_for(owner: Object = null) -> void:
	if owner == null or owner == _owner:
		visible = false
		_owner = null


func owned_by(owner: Object) -> bool:
	return visible and _owner == owner


func attach(c: Control, text_fn: Callable) -> void:
	c.mouse_entered.connect(func(): show_text(text_fn.call(), c))
	c.mouse_exited.connect(func(): hide_for(c))


func _place() -> void:
	var vp := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var p := mouse + Vector2(22, 18)
	if p.x + size.x > vp.x - 8:
		p.x = mouse.x - size.x - 22
	if p.y + size.y > vp.y - 8:
		p.y = mouse.y - size.y - 18
	position = p
