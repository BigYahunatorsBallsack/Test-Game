--!strict
-- Soziales (Paket 5.7): Freunde-Bonus, Wochen-Rangliste und Sammlung besuchen. Nur Werte, keine Logik
-- (Logic/Social). Preise und Faktoren stehen nie im Code.

export type Friends = {
    perFriendBp: number, -- Hundertstel-Prozent Münzen je Freund im Server (1000 = 10 %)
    maxBp: number, -- Obergrenze des Bonus (5000 = 50 %)
}

export type Leaderboard = {
    topCount: number, -- so viele Plätze zeigt die Rangliste
    maxFriends: number, -- so viele Freunde zeigt die Liste zum Besuchen (der Besuch wählt einen Platz 1 bis maxFriends)
    writeSeconds: number, -- Mindestabstand zwischen zwei Schreibvorgängen je Spieler
    readSeconds: number, -- so oft liest der Server die Top-Liste neu (Zwischenspeicher)
    friendCacheSeconds: number, -- so lange gilt die Freundesliste zum Besuchen (danach "notFriend", neu laden)
    store: string, -- OrderedDataStore je Woche: Name + "_" + Wochenindex
    showcaseStore: string, -- DataStore mit dem öffentlichen Sammlungs-Auszug je Spieler
    studioSuffix: string, -- Zusatz im Namen in Studio, damit Tests nie echte Daten berühren
}

local friends: Friends = {
    perFriendBp = 1000,
    maxBp = 5000,
}

local leaderboard: Leaderboard = {
    topCount = 10,
    maxFriends = 50,
    writeSeconds = 120,
    readSeconds = 60,
    friendCacheSeconds = 300,
    store = "CollectionWeekly_v1",
    showcaseStore = "CollectionShowcase_v1",
    studioSuffix = "_Studio",
}

return {
    friends = friends,
    leaderboard = leaderboard,
}
