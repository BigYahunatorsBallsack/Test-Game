--!strict
-- Fundstellen im Sand (Überarbeitung Ü3, Plan "Plan Ü3: Fundstellen im Sand"). Regeln in
-- Logic/FindSpots, Server-Teil im Finds-Service, Glitzern in Controllers/FindSpots.
--
-- Der Server legt je Spieler Fundstellen um die Stelle an, an der er gerade gräbt. Wer in der Zelle
-- einer Stelle bis zu ihrer Schicht sticht, findet ein Fundstück. Die Seltenheit wird erst dann
-- gewürfelt, mit der unveränderten Quotentabelle aus Data/FindOdds. Startwerte, Balancing in Ü10.

return {
    -- Höchstens so viele Stellen je Spieler gleichzeitig.
    maxActive = 3,
    -- Neue Stellen je Sekunde echtes Graben in Zone 1 ohne Boni (1/40 = im Schnitt alle 40 s).
    -- Zone, Glück-Ast, Glücks-Boost und Wetter wirken als Faktor, wie bei der Fundchance.
    spawnPerSecond = 1 / 40,
    -- Abstand einer neuen Stelle von der Stichstelle (Studs, waagrecht).
    minDistanceStuds = 8,
    maxDistanceStuds = 30,
    -- So viele Versuche, einen Punkt mit Sand zu finden, bevor die Stelle ausfällt.
    spawnTries = 4,
    -- Nach so vielen Sekunden verschwindet eine Stelle, die niemand ausgräbt.
    lifetimeSeconds = 120,
    -- Gewichte der Schicht einer neuen Stelle (Index = Schicht aus Data/Deposits).
    layerWeights = { 20, 60, 20 },
    -- Zufallsfunde ohne Stelle: Faktor auf die bisherige Fundchance je Sekunde Graben.
    baseChanceFactor = 0.25,
    -- Erster Fund sicher: nach so vielen angenommenen Stichen ohne jeden Fund entsteht eine Stelle in
    -- Schicht 1 direkt vor dem Spieler (eine Zelle weiter in Blickrichtung). Nur einmal je Sitzung.
    firstFindStabs = 20,
    -- Strahl auf dem Server beim Suchen eines Punkts: so weit über der Stichhöhe beginnen, so lang.
    rayUpStuds = 30,
    rayLengthStuds = 60,
    -- Client: Glitzern sichtbar bis zu dieser Entfernung (Studs).
    glitterDistanceStuds = 40,
}
