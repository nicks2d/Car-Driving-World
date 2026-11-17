class_name ContactShadow
extends RefCounted
## Weicher Kontaktschatten unter Autos (eigenes Auto: CarModel, Verkehr: Traffic): ein Decal, das von oben
## einen dunklen, zum Rand weich auslaufenden Fleck auf Straße und Boden legt. Er erdet das Auto auch bei
## bedecktem Himmel, nachts und im Schatten, wo die Sonne keinen Schatten wirft.

## Größe des Schattenbilds (Bildpunkte) und wie weit der Fleck über das Auto hinausreicht (Meter)
const TEXTURE_SIZE: int = 64
const MARGIN := Vector2(1.3, 1.2)

static var _texture: ImageTexture


## Decal für ein Auto mit dieser Grundfläche (Breite × Länge). Mitte = Boden unter der Automitte.
static func make(footprint: Vector2, strength: float = 0.75) -> Decal:
	var decal := Decal.new()
	decal.size = Vector3(footprint.x + MARGIN.x, 0.8, footprint.y + MARGIN.y)
	decal.texture_albedo = _shadow_texture()
	decal.modulate = Color(1.0, 1.0, 1.0, strength)
	decal.albedo_mix = 1.0
	# Oben und unten weich auslaufen, nur auf etwa waagerechten Flächen
	decal.upper_fade = 0.4
	decal.lower_fade = 0.4
	decal.normal_fade = 0.4
	return decal


## Schwarzer, abgerundeter Fleck: in der Mitte dunkel, zum Rand weich durchsichtig
static func _shadow_texture() -> ImageTexture:
	if _texture:
		return _texture
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var p := Vector2((x + 0.5) / TEXTURE_SIZE * 2.0 - 1.0, (y + 0.5) / TEXTURE_SIZE * 2.0 - 1.0)
			# Abstand zu einem abgerundeten Rechteck in der Mitte (etwa die Grundfläche des Autos); der Rand
			# (MARGIN) läuft weich aus
			var outside := (p.abs() - Vector2(0.5, 0.72)).max(Vector2.ZERO).length()
			var alpha := pow(1.0 - smoothstep(0.0, 0.42, outside), 1.6) * 0.95
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	_texture = ImageTexture.create_from_image(image)
	return _texture
