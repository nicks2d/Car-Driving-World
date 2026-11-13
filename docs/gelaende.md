# Gelände, Horizont-Ring, Vegetation

## Welt-Formel und Rauschen

- Welt-Formel: `scripts/world_gen.gd` (Resource, im Inspector am Main-Node). Seed 1337.
  Höhe = Talboden (großräumig 60–180 m) + Relief (Hügel + Bergketten bis ~1.900 m).
  Flüsse = Null-Linien eines Rauschens, das Relief wird dort zum Tal abgesenkt.
  Seen = höchstens einer pro 2,5-km-Zelle, Wasserhöhe knapp unter dem tiefsten Randpunkt.
- FastNoiseLite-Falle: Domain Warp hat standardmäßig 5 Stufen mit Faktor 6, das macht
  das Gelände aus der Nähe stachelig. Deshalb `domain_warp_fractal_octaves = 2`.

## Kacheln, Detailstufen, Laden

- Terrain: Kacheln à 256 m, Detailstufen mit 2/4/8/16 m Raster (Grenzen 450/900/1500 m),
  Sichtweite 2 km, Kollision (HeightMapShape3D, skaliert) bis 320 m. Berechnung im
  WorkerThreadPool, max. 2 Kacheln pro Bild einbauen. Schürzen gegen LOD-Lücken.
- Laden in Fahrtrichtung: Gelände-Kacheln und Straßen werden vom Punkt 3 s Fahrweg voraus
  (höchstens 400 m) aus sortiert, fehlende Kacheln vor feineren Detailstufen; ab 150 km/h
  rechnen 8 statt 6 Kacheln gleichzeitig (`lookahead_seconds`, `fast_parallel_jobs`).
- Sprünge (Reset, Teleport, > 50 m in einem Bild): Fehlt dort Gelände oder liegt der Ring noch
  nicht passend, zeigt `game.gd` den Ladebildschirm und hält das Auto fest, bis alles da ist.
- Gelände-Kacheln warten, bis alle Straßen in ihrer Nähe berechnet sind.

## Horizont-Ring

- Horizont-Ring 0,4–26 km (110 × 720 Punkte). Er versinkt im Shader nur dort, wo schon
  Gelände-Kacheln liegen (`TerrainManager.chunk_mask`, 32 × 32 Pixel = Kacheln um das Auto,
  wird bei jeder fertigen/gelöschten Kachel neu gezeichnet). Am inneren Rand eine Schürze bis
  -400 m. Früher sank er stur im Umkreis von 1,5 km um die Kamera, mit offenem Innenrand bei
  1,2 km: Fehlten die Kacheln noch, hing dort ein „schwebender Felsbogen“ in der Luft.
  Ab 700–1500 m blendet der Terrain-Shader auf die Durchschnittsfarben der Texturen um,
  damit Kacheln und Ring gleich aussehen.

## Gelände an Straßen

- Gelände an Straßen (`road_query.gd`): Fahrbahn ist immer „hart“, daneben Böschung mit
  Neigung 0,65; bei mehreren Straßen müssen alle Höhenbereiche gleichzeitig gelten
  (sonst Wände zwischen Serpentinen-Ästen).
- Gelände: Böschungs-Halbkreise an Stückenden entfallen, wenn in ihrer Reichweite eine Brücke
  oder ein Tunnel beginnt (sonst Erdbuckel quer über der Fahrbahn am Brückenanfang).
- Erdbuckel am Brückenanfang (behoben, z. B. Landstraße bei (510, 330), Fluss): Stücke ganz auf einer
  Brücke verändern das Gelände nicht (darunter bleibt Tal/Fluss), hatten aber auch keine Obergrenze.
  Lag das Ufer höher als die Fahrbahn, ragte es durch. Jetzt gilt dort eine Obergrenze
  (`RoadQuery._bridge_ceiling`): Plattenunterseite (1,4 m) − 0,3 m, seitlich mit der Böschungsneigung
  ansteigend, nur entlang der Brücke (± 2 m über die Stückenden), nicht über ihre Enden hinaus
  (sonst würde sie am Tunnelportal in den Berg schneiden). Tunnel-Prüfwerkzeug danach: 0 Stellen.
  Der Test-Autopilot fährt dort jetzt mit 89 km/h durch. An der Kreuzung Mühlingen (945, 600)
  schneidet er die Kurve und bleibt manchmal hängen (Autopilot, keine Straßen-Sache).

## Vegetation

- Vegetation (M6): Modelle werden im Code gebaut (`vegetation_meshes.gd`), weil Poly Havens
  Bäume Millionen Dreiecke haben und Kenney Comic-Stil ist. Fichte ~180, Laubbaum ~150
  Dreiecke, ferne Versionen ~15. Bäume/Büsche/Felsen verteilt die Gelände-Kachel im
  Hintergrund (festes Zufallsraster pro Kachel, deterministisch), MultiMesh pro Art und Kachel,
  bis Detailstufe 2 (~1,5 km), Schatten nur Detailstufe 0. Gras: `grass_manager.gd`,
  16-m-Felder bis 56 m ums Auto, 3 Büschel/m².
- Bäume/Büsche/Felsen halten Abstand zur Straße nach Kronenradius (+ Böschungskante), wachsen
  nicht unter Brücken, auf Kreuzungen oder wo das Gelände für die Straße verändert wurde.
  Höhe exakt wie im Mesh (zwei Dreiecke pro Quadrat), Stämme sinken am Hang etwas ein.
- Vertex-Farben kommen im eigenen Shader unverändert an (kein sRGB → linear). Deshalb rechnet
  `foliage.gdshader` sie selbst um, sonst sind die Bäume knallgrün.
- Kollision von Stämmen/Felsen direkt über den PhysicsServer, ein Körper pro 64 × 64 m.
  Ein Körper mit 1000 Formen kostete 33 ms (Ruckler), so sind es ~3,5 ms pro Kachel.
