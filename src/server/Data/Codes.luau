--!strict
-- Codes (Paket 5.2). Diese Tabelle liegt NUR auf dem Server (ServerScriptService, wird nie zum Client
-- repliziert). Die Regeln stehen in src/shared/Logic/Codes (normalize, redeem, attempt, check), der
-- Service Services/Codes prüft die Tabelle beim Serverstart mit Logic/Codes.check und bricht bei
-- Fehlern ab.
--
-- VOR DEM START: Die beiden Beispiel-Codes unten durch echte Codes ersetzen. Kein Code-Text darf unter
-- src/shared oder src/client stehen (ein Lune-Test in tests/codes.spec.luau sucht danach), auch nicht
-- als Platzhalter oder Beispiel in einem Eingabefeld.
--
-- Eine Zeile je Code:
--   id        Schlüssel in profile.codes (Code-ID -> true), Buchstaben, Ziffern, _ und -, höchstens 32
--             Zeichen. Nie umbenennen und nie für einen anderen Code wiederverwenden: Eine umbenannte ID
--             wäre für alle wieder einlösbar, eine wiederverwendete für alle gesperrt, die die alte
--             eingelöst haben. Einen alten Code aus der Liste zu löschen ist erlaubt (er wird dann
--             "ungültig"), seine ID darf danach aber nicht wiederkommen.
--   code      Text, den der Spieler eingibt, schon normalisiert: nur A-Z, 0-9 und Bindestrich, 1 bis 24
--             Zeichen. Groß- und Kleinschreibung und Leerraum am Rand der Eingabe zählen nicht.
--   reward    { kind = "gems", amount = N }                     N ganz, 1 bis 1000
--             { kind = "coinBoost", seconds = N }               Münz-Boost, N ganz, 1 bis 86400
--             { kind = "luck", seconds = N }                    Glücks-Boost, N ganz, 1 bis 86400
--             Nie Kisten, Items oder Robux (Logic/Codes kennt nur diese drei Arten).
--   startsAt  optional: Unix-Zeit (UTC, Server-Uhr), ab der der Code gilt
--   endsAt    optional: Unix-Zeit (UTC, Server-Uhr), bis zu der der Code gilt (einschließlich)
-- Vor startsAt und nach endsAt antwortet der Server wie bei einem unbekannten Code ("invalid").

local list = {
    {
        id = "welcome",
        code = "WILLKOMMEN",
        reward = { kind = "gems", amount = 50 },
    },
    {
        id = "likes1000",
        code = "1000LIKES",
        reward = { kind = "coinBoost", seconds = 1200 },
    },
}

return {
    list = list,
}
