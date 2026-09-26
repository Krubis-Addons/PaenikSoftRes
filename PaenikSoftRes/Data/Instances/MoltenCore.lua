-- Molten Core (Classic). ItemIDs, npcIDs und DisplayIDs aus AtlasLootClassic (data.lua), per Skript übernommen.
local _, ns = ...

ns.LootData:RegisterStaticInstance({
    key = "mc",
    name = "Molten Core",
    mapID = 409,
    isRaid = true,
    maxPlayers = 40,
    encounters = {
        {
            name = "Lucifron",
            npcID = 12118,
            displayID = 13031,
            items = {
                16800, -- Arcanist Boots
                16805, -- Felheart Gloves
                16829, -- Cenarion Boots
                16837, -- Earthfury Boots
                16859, -- Lawbringer Boots
                16863, -- Gauntlets of Might
                18870, -- Helm of the Lifegiver
                17109, -- Choker of Enlightenment
                19145, -- Robe of Volatile Power
                19146, -- Wristguards of Stability
                18872, -- Manastorm Leggings
                18875, -- Salamander Scale Pants
                18861, -- Flamewaker Legplates
                18879, -- Heavy Dark Iron Ring
                19147, -- Ring of Spell Power
                17077, -- Crimson Shocker
                18878, -- Sorcerous Dagger
                16665, -- Tome of Tranquilizing Shot
            },
        },
        {
            name = "Magmadar",
            npcID = 11982,
            displayID = 10193,
            items = {
                16814, -- Pants of Prophecy
                16796, -- Arcanist Leggings
                16810, -- Felheart Pants
                16822, -- Nightslayer Pants
                16835, -- Cenarion Leggings
                16847, -- Giantstalker's Leggings
                16843, -- Earthfury Legguards
                16855, -- Lawbringer Legplates
                16867, -- Legplates of Might
                18203, -- Eskhandar's Right Claw
                17065, -- Medallion of Steadfast Might
                18829, -- Deep Earth Spaulders
                18823, -- Aged Core Leather Gloves
                19143, -- Flameguard Gauntlets
                19136, -- Mana Igniting Cord
                18861, -- Flamewaker Legplates
                19144, -- Sabatons of the Flamewalker
                18824, -- Magma Tempered Boots
                18821, -- Quick Strike Ring
                18820, -- Talisman of Ephemeral Power
                19142, -- Fire Runed Grimoire
                17069, -- Striker's Mark
                17073, -- Earthshaker
                18822, -- Obsidian Edged Blade
            },
        },
        {
            name = "Gehennas",
            npcID = 12259,
            displayID = 13030,
            items = {
                16812, -- Gloves of Prophecy
                16826, -- Nightslayer Gloves
                16849, -- Giantstalker's Boots
                16839, -- Earthfury Gauntlets
                16860, -- Lawbringer Gauntlets
                16862, -- Sabatons of Might
                18870, -- Helm of the Lifegiver
                19145, -- Robe of Volatile Power
                19146, -- Wristguards of Stability
                18872, -- Manastorm Leggings
                18875, -- Salamander Scale Pants
                18861, -- Flamewaker Legplates
                18879, -- Heavy Dark Iron Ring
                19147, -- Ring of Spell Power
                17077, -- Crimson Shocker
                18878, -- Sorcerous Dagger
            },
        },
        {
            name = "Garr",
            npcID = 12057,
            displayID = 12110,
            items = {
                18564, -- Bindings of the Windseeker
                16813, -- Circlet of Prophecy
                16795, -- Arcanist Crown
                16808, -- Felheart Horns
                16821, -- Nightslayer Cover
                16834, -- Cenarion Helm
                16846, -- Giantstalker's Helmet
                16842, -- Earthfury Helmet
                16854, -- Lawbringer Helm
                16866, -- Helm of Might
                18829, -- Deep Earth Spaulders
                18823, -- Aged Core Leather Gloves
                19143, -- Flameguard Gauntlets
                19136, -- Mana Igniting Cord
                18861, -- Flamewaker Legplates
                19144, -- Sabatons of the Flamewalker
                18824, -- Magma Tempered Boots
                18821, -- Quick Strike Ring
                18820, -- Talisman of Ephemeral Power
                19142, -- Fire Runed Grimoire
                17066, -- Drillborer Disk
                17071, -- Gutgore Ripper
                17105, -- Aurastone Hammer
                18832, -- Brutality Blade
                18822, -- Obsidian Edged Blade
            },
        },
        {
            name = "Shazzrah",
            npcID = 12264,
            displayID = 13032,
            items = {
                16811, -- Boots of Prophecy
                16801, -- Arcanist Gloves
                16803, -- Felheart Slippers
                16824, -- Nightslayer Boots
                16831, -- Cenarion Gloves
                16852, -- Giantstalker's Gloves
                18870, -- Helm of the Lifegiver
                19145, -- Robe of Volatile Power
                19146, -- Wristguards of Stability
                18872, -- Manastorm Leggings
                18875, -- Salamander Scale Pants
                18861, -- Flamewaker Legplates
                18879, -- Heavy Dark Iron Ring
                19147, -- Ring of Spell Power
                17077, -- Crimson Shocker
                18878, -- Sorcerous Dagger
            },
        },
        {
            name = "Baron Geddon",
            npcID = 12056,
            displayID = 12129,
            items = {
                18563, -- Bindings of the Windseeker
                16797, -- Arcanist Mantle
                16807, -- Felheart Shoulder Pads
                16836, -- Cenarion Spaulders
                16844, -- Earthfury Epaulets
                16856, -- Lawbringer Spaulders
                18829, -- Deep Earth Spaulders
                18823, -- Aged Core Leather Gloves
                19143, -- Flameguard Gauntlets
                19136, -- Mana Igniting Cord
                18861, -- Flamewaker Legplates
                19144, -- Sabatons of the Flamewalker
                18824, -- Magma Tempered Boots
                18821, -- Quick Strike Ring
                17110, -- Seal of the Archmagus
                18820, -- Talisman of Ephemeral Power
                19142, -- Fire Runed Grimoire
                18822, -- Obsidian Edged Blade
            },
        },
        {
            name = "Golemagg the Incinerator",
            npcID = 11988,
            displayID = 11986,
            items = {
                16815, -- Robes of Prophecy
                16798, -- Arcanist Robes
                16809, -- Felheart Robes
                16820, -- Nightslayer Chestpiece
                16833, -- Cenarion Vestments
                16845, -- Giantstalker's Breastplate
                16841, -- Earthfury Vestments
                16853, -- Lawbringer Chestguard
                16865, -- Breastplate of Might
                17203, -- Sulfuron Ingot
                18829, -- Deep Earth Spaulders
                18823, -- Aged Core Leather Gloves
                19143, -- Flameguard Gauntlets
                19136, -- Mana Igniting Cord
                18861, -- Flamewaker Legplates
                19144, -- Sabatons of the Flamewalker
                18824, -- Magma Tempered Boots
                18821, -- Quick Strike Ring
                18820, -- Talisman of Ephemeral Power
                19142, -- Fire Runed Grimoire
                17072, -- Blastershot Launcher
                17103, -- Azuresong Mageblade
                18822, -- Obsidian Edged Blade
                18842, -- Staff of Dominance
            },
        },
        {
            name = "Sulfuron Harbinger",
            npcID = 12098,
            displayID = 13030,
            items = {
                16816, -- Mantle of Prophecy
                16823, -- Nightslayer Shoulder Pads
                16848, -- Giantstalker's Epaulets
                16868, -- Pauldrons of Might
                18870, -- Helm of the Lifegiver
                19145, -- Robe of Volatile Power
                19146, -- Wristguards of Stability
                18872, -- Manastorm Leggings
                18875, -- Salamander Scale Pants
                18861, -- Flamewaker Legplates
                18879, -- Heavy Dark Iron Ring
                19147, -- Ring of Spell Power
                17077, -- Crimson Shocker
                18878, -- Sorcerous Dagger
                17074, -- Shadowstrike
            },
        },
        {
            name = "Majordomo Executus",
            npcID = 12018,
            displayID = 12029,
            items = {
                19139, -- Fireguard Shoulders
                18810, -- Wild Growth Spaulders
                18811, -- Fireproof Cloak
                18808, -- Gloves of the Hypnotic Flame
                18809, -- Sash of Whispered Secrets
                18812, -- Wristguards of True Flight
                18806, -- Core Forged Greaves
                19140, -- Cauterizing Band
                18805, -- Core Hound Tooth
                18803, -- Finkle's Lava Dredger
                18703, -- Ancient Petrified Leaf
                18646, -- The Eye of Divinity
            },
        },
        {
            name = "Ragnaros",
            npcID = 11502,
            displayID = 11121,
            items = {
                17204, -- Eye of Sulfuras
                19017, -- Essence of the Firelord
                16922, -- Leggings of Transcendence
                16915, -- Netherwind Pants
                16930, -- Nemesis Leggings
                16909, -- Bloodfang Pants
                16901, -- Stormrage Legguards
                16938, -- Dragonstalker's Legguards
                16946, -- Legplates of Ten Storms
                16954, -- Judgement Legplates
                16962, -- Legplates of Wrath
                17082, -- Shard of the Flame
                18817, -- Crown of Destruction
                18814, -- Choker of the Fire Lord
                17102, -- Cloak of the Shrouded Mists
                17107, -- Dragon's Blood Cape
                19137, -- Onslaught Girdle
                17063, -- Band of Accuria
                19138, -- Band of Sulfuras
                18815, -- Essence of the Pure Flame
                17106, -- Malistar's Defender
                18816, -- Perdition's Blade
                17104, -- Spinal Reaper
                17076, -- Bonereaver's Edge
            },
        },
    },
})
