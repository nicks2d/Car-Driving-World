class_name OpenWindows
extends Node
## Fenster runter (Taste V): Die Seitenscheiben fahren in fold_seconds nach unten
## (Car.windows_open, Shader car_glass.gdshader). Offen wird alles deutlich lauter: Motor und
## Auspuff (Bus „Motor“), Regen und Wind (Bus „Umgebung“), der Tunnel hallt stärker, dazu
## rauscht der Fahrtwind mit dem Tempo (Rauschen im Code erzeugt).
## Beim SL 65 bleibt das Dach drauf: Das Modell hat kein eigenes Dachteil (Carbon-Dach ist Teil
## der Karosserie), es gibt also wie bei allen Autos die Fenster.

@export var car: Car
## So lange brauchen die Scheiben ganz nach unten (Sekunden)
@export var fold_seconds: float = 1.6
## So viel lauter bei offenen Fenstern (dB)
@export var engine_boost_db: float = 6.0
@export var ambient_boost_db: float = 7.0
## Fahrtwind bei 100 km/h (dB)
@export var wind_volume_db: float = -13.0

var open: bool = false
var _boosts: Array[AudioEffectAmplify] = []
var _reverb: AudioEffectReverb
var _reverb_wet: float = 0.0
var _wind: AudioStreamPlayer


func _ready() -> void:
	# Lautstärke über einen eigenen Verstärker je Bus (die Regler im Menü bleiben unberührt)
	for bus_name: String in ["Motor", "Umgebung"]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var amplify := AudioEffectAmplify.new()
		amplify.volume_db = 0.0
		AudioServer.add_bus_effect(bus, amplify)
		_boosts.append(amplify)
	var tunnel := AudioServer.get_bus_index("Tunnel")
	if tunnel >= 0:
		for k in AudioServer.get_bus_effect_count(tunnel):
			var effect := AudioServer.get_bus_effect(tunnel, k)
			if effect is AudioEffectReverb:
				_reverb = effect
				_reverb_wet = _reverb.wet
	_wind = AudioStreamPlayer.new()
	_wind.stream = _wind_loop()
	_wind.bus = "Umgebung"
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()


## Fahrtwind: tiefes, gefiltertes Rauschen (1,5 s, an den Enden überblendet)
func _wind_loop() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 1.5)
	var fade := int(rate * 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var samples := PackedFloat32Array()
	samples.resize(count)
	var a := 0.0
	var b := 0.0
	for i in count:
		a += (rng.randf_range(-1.0, 1.0) - a) * 0.08
		b += (a - b) * 0.12
		samples[i] = b * 2.2
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[count - fade + i] * (1.0 - w)
	var data := PackedByteArray()
	data.resize((count - fade) * 2)
	for i in count - fade:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count - fade
	return stream


func _process(delta: float) -> void:
	if car == null:
		return
	if car.throttle_enabled and not get_tree().paused and Input.is_action_just_pressed("toggle_windows"):
		open = not open
	car.windows_open = move_toward(car.windows_open, 1.0 if open else 0.0, delta / fold_seconds)
	var amount := car.windows_open
	if _boosts.size() >= 1:
		_boosts[0].volume_db = engine_boost_db * amount
	if _boosts.size() >= 2:
		_boosts[1].volume_db = ambient_boost_db * amount
	if _reverb:
		_reverb.wet = _reverb_wet + 0.25 * amount
	var kmh := car.linear_velocity.length() * 3.6
	var loud := wind_volume_db + 20.0 * log(maxf(kmh, 5.0) / 100.0) / log(10.0)
	_wind.volume_db = loud if amount > 0.01 else -80.0
	_wind.volume_db += 20.0 * log(maxf(amount, 0.01)) / log(10.0)
	_wind.pitch_scale = clampf(0.7 + kmh / 250.0, 0.6, 1.8)
