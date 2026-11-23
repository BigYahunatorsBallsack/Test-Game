--!strict
-- Event-Kalender (Paket 5.4, Konzept: "vierwöchige Saisons mit eigener Event-Zone, Event-Kiste und
-- Pass"). Eine Zeile je Saison. Die Regeln stehen in Logic/Seasons (Woche, Phase, Kiste offen?),
-- DataCheck.checkSeasons prüft die Tabelle beim Serverstart.
--
-- Eine neue Saison anlegen (kein Logik-Code):
--  1. Data/Crates: neue Kiste kopieren (z. B. "event_s2", Quoten wie die Goldkiste, eventOnly = true).
--  2. Data/CrateItems: die Items der Saison mit `crates = { "event_s2" }` eintragen.
--  3. Hier eine Zeile mit `crateId = "event_s2"` und dem Startdatum. Fertig.
--  Mit Pass (Paket 5.5): Event-Zone in Data/Zones (`events`), Stufen in Data/SeasonPass
--  (`bySeason.<saisonId>`) und ein eigenes Developer Product in Data/Products (z. B. "season_pass_2",
--  oneTime = false), hier `zoneId` und `passId` setzen. Der Kauf-Handler wird für jede passId
--  automatisch angemeldet (Services/SeasonPasses).
--
-- Regeln (DataCheck erzwingt sie):
--  * Eine Saison dauert immer 4 Wochen (#phases * 7 Tage), das Ende ist ausschließend.
--  * Der Start ist ein Montag, 0 Uhr UTC ("JJJJ-MM-TT"). So liegt das Server-Event "Der Koloss" in
--    Woche 2 sicher auf Samstag und Sonntag.
--  * Saisons überlappen nicht. Zwischen zwei Saisons darf eine Pause liegen.
--  * Jede `eventOnly`-Kiste gehört zu genau einer Saison.
--  * Alte Saisons nie aus der Liste löschen: Items und Pity im Profil bleiben ohnehin erhalten, aber
--    die Tabelle ist der Verlauf des Spiels.
--  * Nach dem Ende der Saison bleibt alles im Profil; nur das Öffnen der Event-Kiste ist gesperrt.

export type Phase = {
    id: string, -- "start", "koloss", "items", "finale" (spätere Pakete hängen Schalter daran)
    name: string, -- Anzeigename der Woche
    crateOpen: boolean, -- in dieser Woche darf die Event-Kiste der Saison geöffnet werden
    zoneOpen: boolean, -- in dieser Woche ist die Event-Zone der Saison offen (Paket 5.5)
    hint: string?, -- Hinweis in der Kistenzeile für diese Woche (optional)
}

export type Season = {
    id: string, -- Saison-ID (Schlüssel für spätere Pakete, nie umbenennen)
    name: string, -- Anzeigename
    startDate: string, -- "JJJJ-MM-TT", ein Montag, 0 Uhr UTC
    crateId: string, -- Event-Kiste aus Data/Crates (eventOnly = true)
    zoneId: string?, -- Event-Zone aus Data/Zones (`Zones.events`, Paket 5.5)
    passId: string?, -- Saison-Pass aus Data/Products (Paket 5.5)
}

-- Die vier Wochen einer Saison, in der Reihenfolge der Wochen.
local phases: { Phase } = {
    { id = "start", name = "Saisonstart", crateOpen = true, zoneOpen = true },
    { id = "koloss", name = "Koloss-Woche", crateOpen = true, zoneOpen = true },
    { id = "items", name = "Event-Items", crateOpen = true, zoneOpen = true },
    { id = "finale", name = "Finale", crateOpen = true, zoneOpen = true, hint = "Letzte Woche: letzte Chance auf die Event-Kiste" },
}

local list: { Season } = {
    -- Platzhalter-Startdatum: vor dem Launch auf den echten Saisonstart (Montag) setzen.
    -- passId (Paket 5.5b): Developer Product des Saison-Passes in Data/Products (oneTime = false). Jede
    -- Saison bekommt ihr eigenes Produkt, ein Produkt gehört zu höchstens einer Saison (DataCheck).
    { id = "season_1", name = "Saison 1", startDate = "2027-01-04", crateId = "event", zoneId = "season_camp", passId = "season_pass" },
}

return {
    phases = phases,
    list = list,
}
