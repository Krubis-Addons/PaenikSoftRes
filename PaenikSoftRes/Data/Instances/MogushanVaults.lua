-- Mogu'shan-Gewölbe (Mists of Pandaria, Stufe 14). ItemIDs aus AtlasLootClassic (data-mop.lua),
-- per Skript übernommen. Normal und Heroisch haben eigene ItemIDs, daher zwei Instanzen.
-- Bosse ohne displayID: Porträt über ejEncounterID (LootData, nur wenn das Dungeonkompendium Daten hat).
local _, ns = ...

ns.LootData:RegisterStaticInstance({
    key = "msv",
    name = "Mogu'shan Vaults",
    mapID = 1008,
    isRaid = true,
    maxPlayers = 25,
    encounters = {
        {
            name = "The Stone Guard",
            ejEncounterID = 679, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                85979, -- Cape of Three Lanterns
                89768, -- Claws of Amethyst
                89767, -- Ruby-Linked Girdle
                85978, -- Jade Dust Leggings
                85977, -- Stonebound Cinch
                85926, -- Stoneflesh Leggings
                85976, -- Sixteen-Fanged Crown
                89766, -- Stonefang Chestguard
                85923, -- Stonemaw Armguards
                86134, -- Star-Stealer Waistguard
                85975, -- Heavenly Jade Greatboots
                85925, -- Jasper Clawfeet
                85922, -- Beads of the Mogu'shi
                85924, -- Dagger of the Seven Stars
            },
        },
        {
            name = "Feng the Accursed",
            ejEncounterID = 689, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                86082, -- Arrow Breaking Windcloak
                85985, -- Cloak of Peacock Feathers
                85990, -- Imperial Ghostbinder's Robes
                85989, -- Hood of Cursed Dreams
                85982, -- Tomb Raider's Girdle
                85987, -- Chain of Shadow
                85980, -- Wildfire Worldwalkers
                85984, -- Nullification Greathelm
                85983, -- Bracers of Six Oxen
                85988, -- Legplates of Sagacious Shadows
                85986, -- Amulet of Seven Curses
                89803, -- Feng's Ring of Dreams
                89802, -- Feng's Seal of Binding
                89424, -- Fan of Fiery Winds
            },
        },
        {
            name = "Gara'jal the Spiritbinder",
            ejEncounterID = 682, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                86041, -- Shadowsummoner Spaulders
                85997, -- Sandals of the Severed Soul
                85995, -- Netherrealm Shoulderpads
                86039, -- Spaulders of the Divided Mind
                85993, -- Fetters of Death
                86040, -- Leggings of Imprisoned Will
                86027, -- Bindings of Ancient Spirits
                89817, -- Bonded Soul Bracers
                85992, -- Sollerets of Spirit Splitting
                85991, -- Soulgrasp Choker
                86038, -- Circuit of the Frail Soul
                85994, -- Gara'kal, Fist of the Spiritbinder
                85996, -- Eye of the Ancient Spirit
            },
        },
        {
            name = "The Spirit Kings",
            ejEncounterID = 687, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                86082, -- Arrow Breaking Windcloak
                89819, -- Mindshard Drape
                86129, -- Hood of Blind Eyes
                86128, -- Undying Shadow Grips
                86127, -- Bracers of Dark Thoughts
                89818, -- Bracers of Violent Meditation
                86081, -- Subetai's Pillaging Leggings
                86084, -- Meng's Treads of Insanity
                86080, -- Shoulderguards of the Unflanked
                86076, -- Breastplate of the Kings' Guard
                86086, -- Girdle of Delirious Visions
                86047, -- Amulet of the Hidden Kings
                86083, -- Zian's Choker of Coalesced Shadow
                86071, -- Screaming Tiger, Qiang's Unbreakable Polearm
                86075, -- Steelskin, Qiang's Impervious Shield
            },
        },
        {
            name = "Elegon",
            ejEncounterID = 726, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                89822, -- Galaxyfire Girdle
                86139, -- Orbital Belt
                86136, -- Chestguard of Total Annihilation
                86138, -- Phasewalker Striders
                86141, -- Shoulders of Empyreal Focus
                89821, -- Crown of Keening Stars
                86135, -- Starcrusher Gauntlets
                89824, -- Band of Bursting Novas
                86132, -- Bottle of Infinite Stars
                86133, -- Light of the Cosmos
                86131, -- Vial of Dragon's Blood
                86130, -- Elegion, the Fanged Crescent
                86140, -- Starshatter
                86137, -- Torch of the Celestial Spark
            },
        },
        {
            name = "Will of the Emperor",
            ejEncounterID = 677, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                86151, -- Hood of Focused Energy
                86146, -- Crown of Opportunistic Strikes
                86150, -- Magnetized Leggings
                89820, -- Dreadeye Gaze
                89825, -- Enameled Grips of Solemnity
                87827, -- Grips of Terra Cotta
                86149, -- Spaulders of the Emperor's Rage
                89823, -- Chestguard of Eternal Vigilance
                86145, -- Jang-xi's Devastating Legplates
                86152, -- Worldwaker Cachabon
                86144, -- Lei Shin's Final Orders
                86147, -- Qin-xi's Polarizing Seal
                86148, -- Tihan, Scepter of the Sleeping Emperor
                86142, -- Fang Kung, Spark of Titans
            },
        },
    },
    filler = {
        86043, -- Jade Bandit Figurine
        86042, -- Jade Charioteer Figurine
        86045, -- Jade Courtesan Figurine
        86044, -- Jade Magistrate Figurine
        86046, -- Jade Warlord Figurine
    },
})

ns.LootData:RegisterStaticInstance({
    key = "msvh",
    name = "Mogu'shan Vaults (Heroisch)",
    mapID = 1008,
    isRaid = true,
    maxPlayers = 25,
    encounters = {
        {
            name = "The Stone Guard",
            ejEncounterID = 679, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                87018, -- Cape of Three Lanterns
                89931, -- Claws of Amethyst
                89930, -- Ruby-Linked Girdle
                87017, -- Jade Dust Leggings
                87019, -- Stonebound Cinch
                87013, -- Stoneflesh Leggings
                87020, -- Sixteen-Fanged Crown
                89929, -- Stonefang Chestguard
                87014, -- Stonemaw Armguards
                87060, -- Star-Stealer Waistguard
                87021, -- Heavenly Jade Greatboots
                87015, -- Jasper Clawfeet
                87016, -- Beads of the Mogu'shi
                87012, -- Dagger of the Seven Stars
            },
        },
        {
            name = "Feng the Accursed",
            ejEncounterID = 689, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                87044, -- Arrow Breaking Windcloak
                87026, -- Cloak of Peacock Feathers
                87027, -- Imperial Ghostbinder's Robes
                87029, -- Hood of Cursed Dreams
                87022, -- Tomb Raider's Girdle
                87030, -- Chain of Shadow
                87023, -- Wildfire Worldwalkers
                87024, -- Nullification Greathelm
                87025, -- Bracers of Six Oxen
                87031, -- Legplates of Sagacious Shadows
                87028, -- Amulet of Seven Curses
                89933, -- Feng's Ring of Dreams
                89932, -- Feng's Seal of Binding
                89425, -- Fan of Fiery Winds
            },
        },
        {
            name = "Gara'jal the Spiritbinder",
            ejEncounterID = 682, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                87038, -- Shadowsummoner Spaulders
                87037, -- Sandals of the Severed Soul
                87033, -- Netherrealm Shoulderpads
                87041, -- Spaulders of the Divided Mind
                87034, -- Fetters of Death
                87042, -- Leggings of Imprisoned Will
                87043, -- Bindings of Ancient Spirits
                89934, -- Bonded Soul Bracers
                87035, -- Sollerets of Spirit Splitting
                87036, -- Soulgrasp Choker
                87040, -- Circuit of the Frail Soul
                87032, -- Gara'kal, Fist of the Spiritbinder
                87039, -- Eye of the Ancient Spirit
            },
        },
        {
            name = "The Spirit Kings",
            ejEncounterID = 687, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                87044, -- Arrow Breaking Windcloak
                89936, -- Mindshard Drape
                87051, -- Hood of Blind Eyes
                87052, -- Undying Shadow Grips
                87054, -- Bracers of Dark Thoughts
                89935, -- Bracers of Violent Meditation
                87047, -- Subetai's Pillaging Leggings
                87055, -- Meng's Treads of Insanity
                87049, -- Shoulderguards of the Unflanked
                87048, -- Breastplate of the Kings' Guard
                87056, -- Girdle of Delirious Visions
                87045, -- Amulet of the Hidden Kings
                87053, -- Zian's Choker of Coalesced Shadow
                87046, -- Screaming Tiger, Qiang's Unbreakable Polearm
                87050, -- Steelskin, Qiang's Impervious Shield
            },
        },
        {
            name = "Elegon",
            ejEncounterID = 726, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                89938, -- Galaxyfire Girdle
                87064, -- Orbital Belt
                87058, -- Chestguard of Total Annihilation
                87067, -- Phasewalker Striders
                87068, -- Shoulders of Empyreal Focus
                89939, -- Crown of Keening Stars
                87059, -- Starcrusher Gauntlets
                89937, -- Band of Bursting Novas
                87057, -- Bottle of Infinite Stars
                87065, -- Light of the Cosmos
                87063, -- Vial of Dragon's Blood
                87062, -- Elegion, the Fanged Crescent
                87061, -- Starshatter
                87066, -- Torch of the Celestial Spark
            },
        },
        {
            name = "Will of the Emperor",
            ejEncounterID = 677, -- Porträt zur Laufzeit über das Dungeonkompendium
            items = {
                87073, -- Hood of Focused Energy
                87070, -- Crown of Opportunistic Strikes
                87077, -- Magnetized Leggings
                89940, -- Dreadeye Gaze
                89942, -- Enameled Grips of Solemnity
                87825, -- Grips of Terra Cotta
                87078, -- Spaulders of the Emperor's Rage
                89941, -- Chestguard of Eternal Vigilance
                87071, -- Jang-xi's Devastating Legplates
                87076, -- Worldwaker Cachabon
                87072, -- Lei Shin's Final Orders
                87075, -- Qin-xi's Polarizing Seal
                87074, -- Tihan, Scepter of the Sleeping Emperor
                87069, -- Fang Kung, Spark of Titans
            },
        },
    },
})
