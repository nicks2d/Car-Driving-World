extends SceneTree
## Prüfwerkzeug: Wo liegen Talsperren und Wasserfälle? Rechnet sie auf einem Bereich aus (wie im
## Spiel, nur aus dem Seed), gibt Lage, Größe, Rechenzeit und Testbefehle für Fotos aus.
##
## Aufruf (im Projektordner):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/landmarks.gd
##   ... -- --size=40000 (Kantenlänge des Bereichs um 0,0 in Metern)

func _init() -> void:
	var size := 40000.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			size = float(arg.split("=")[1])
	# Die Welt-Formel im Spiel hat nur Standardwerte (main.tscn), also reicht eine neue
	var gen := WorldGen.new()
	gen.setup()
	var half := size * 0.5
	var cells := int(ceilf(size / gen.reservoir_cell_size))
	var start := Time.get_ticks_msec()
	var reservoirs := 0
	var times: Array[float] = []
	for cz in range(-cells / 2, cells / 2 + 1):
		for cx in range(-cells / 2, cells / 2 + 1):
			var t0 := Time.get_ticks_usec()
			var lake := gen.reservoir_in_cell(Vector2i(cx, cz))
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			if lake == null:
				continue
			reservoirs += 1
			var area := 0
			for v in lake.mask:
				area += 1 if v == 1 else 0
			print("Talsperre bei (%d, %d): Mauer %.0f m lang, Krone %.0f m (Fluss %.0f m, %.0f m hoch), See %.2f km², Straße %s" % [
				lake.dam_center.x, lake.dam_center.y, lake.dam_a.distance_to(lake.dam_b), lake.crest, lake.river_level,
				lake.crest - lake.river_level, area * WorldGen.RESERVOIR_STEP * WorldGen.RESERVOIR_STEP / 1.0e6, lake.road_key])
			var below := lake.dam_center + lake.flow * 260.0
			var above := lake.dam_center + lake.flow * 420.0 + Vector2(lake.flow.y, -lake.flow.x) * 120.0
			var c := lake.dam_center
			print("    Fotos: Tal --pos=%d,%d --cam=%d,%d,12 --lookat=%d,%d,14   oben --pos=%d,%d --cam=%d,%d,260 --lookat=%d,%d,0" % [
				c.x, c.y, below.x, below.y, c.x, c.y, c.x, c.y, above.x, above.y, c.x, c.y])
	times.sort()
	print("TALSPERREN: %d auf %.0f × %.0f km, Rechenzeit je Zelle: Mittel %.0f ms, höchstens %.0f ms" % [
		reservoirs, size / 1000.0, size / 1000.0, _mean(times), times.back() if not times.is_empty() else 0.0])
	var falls := gen.waterfalls_near(Rect2(-half, -half, size, size))
	for fall: Dictionary in falls:
		var top: Vector3 = fall["top"]
		var bottom: Vector3 = fall["bottom"]
		print("Wasserfall bei (%d, %d): %.0f m hoch, %.1f m breit, Fuß (%d, %d)" % [top.x, top.z, fall["drop"], fall["width"], bottom.x, bottom.z])
	print("WASSERFÄLLE: %d, alles zusammen %.1f s" % [falls.size(), (Time.get_ticks_msec() - start) / 1000.0])
	quit()


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)
