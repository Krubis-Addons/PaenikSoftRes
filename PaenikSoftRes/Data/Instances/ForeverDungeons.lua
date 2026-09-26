-- WoW: Forever – aktuelle Beta-Dungeons (Stand 2026-09-25).
-- Bosse, ItemIDs und Porträt-DisplayIDs aus ForeverDungeonJournal v1.1 (Exehn), das sie aus den dort
-- in SOURCES.txt genannten Quellen zusammenstellt: foreverchanges.pro, wowforevertalents.com,
-- wowf.io, wowsrc.com und Wowhead Forever. Per Skript übernommen, Quest-Items (Qualität 1) ausgelassen.
-- Beta-Daten: Blizzard kann Drops noch ändern; unbekannte Items blendet LootData zur Laufzeit aus.
local _, ns = ...

ns.LootData:RegisterStaticInstance({
    key = "hot",
    name = "Hall of Thanes",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Faldrim Anvilmar",
            npcID = 261306,
            items = {
                270227, -- Ephemeral Choker
                271096, -- Aetherwisp Bracers
                271097, -- Spiritwraith Drape
            },
        },
        {
            name = "Magmatus",
            items = {
                270230, -- Kindlegem Girdle
                270231, -- Flamefist Grips
                271095, -- Fang of Magmatus
            },
        },
        {
            name = "Plunder",
            npcID = 261311,
            items = {
                270228, -- Golemheart Stave
                271098, -- Golemguard Chest
                270229, -- Treads of the Protector Golem
            },
        },
        {
            name = "Durgen Dirgehammer",
            npcID = 261319,
            items = {
                270256, -- Durgen's Crescent Axe
                270260, -- Direhammer Leggings
                270261, -- Robes of the Disgraced Thane
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "rfc",
    name = "Ragefire Chasm",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Oggleflint",
            npcID = 11517,
            displayID = 11611,
            items = {
                272999, -- Barbaric Crossbow
                272996, -- Trogg Scepter
                272998, -- Bone Knuckles
            },
        },
        {
            name = "Taragaman the Hungerer",
            npcID = 11520,
            displayID = 7970,
            items = {
                14149, -- Subterranean Cape
                14148, -- Crystalline Cuffs
                14145, -- Cursed Felblade
            },
        },
        {
            name = "Jergosh the Invoker",
            npcID = 11518,
            displayID = 11429,
            items = {
                14150, -- Robe of Evocation
                14147, -- Cavedweller Bracers
                14151, -- Chanting Blade
            },
        },
        {
            name = "Bazzalan",
            npcID = 11519,
            displayID = 2007,
            items = {
                273003, -- Searing Dagger
                273007, -- Chasm Walkers
                273005, -- Satyrskin Cloak
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "rol",
    name = "Ruins of Lordaeron",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "The Baron",
            npcID = 250660,
            items = {
                271204, -- Meathook Slicer
                271205, -- Abomination Bones
                271206, -- Leftover Abomination Skin
            },
        },
        {
            name = "Witherfang",
            npcID = 250483,
            items = {
                271201, -- Atrophic Girdle
                271202, -- Witherbite Bracers
                271203, -- Segmented Spider Leg
            },
        },
        {
            name = "The Abandoned",
            npcID = 250631,
            items = {
                271207, -- Wispcloth Leggings
                271208, -- Grip of Fear
                271216, -- Scepter of the Abandoned
            },
        },
        {
            name = "Bjork",
            npcID = 256097,
            items = {
                271209, -- Bonerust Leggings
                271210, -- Tuskwrap Belt
                271217, -- Corpse Chopper
            },
        },
        {
            name = "Rath'mael",
            npcID = 250657,
            items = {
                271213, -- Mirror of Rath'mael
                271214, -- Frostbane Treads
                271215, -- Coldspire Staff
            },
        },
        {
            name = "Viktor the Vile",
            npcID = 256035,
            items = {
                271211, -- Vilewalkers
                271212, -- Bloodied Chestwraps
                271218, -- Vileblood Scimitar
            },
        },
        {
            name = "Lordaeron Captain",
            items = {
                6641, -- Haunting Blade
                6642, -- Phantom Armor
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "dm",
    name = "The Deadmines",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Rhahk'Zor",
            npcID = 644,
            displayID = 14403,
            items = {
                872, -- Rockslicer
                5187, -- Rhahk'Zor's Hammer
                273289, -- Ogre Loincloth
            },
        },
        {
            name = "Miner Johnson",
            npcID = 3586,
            displayID = 556,
            items = {
                5443, -- Gold-plated Buckler
                5444, -- Miner's Cape
            },
        },
        {
            name = "Sneed's Shredder",
            npcID = 642,
            displayID = 1269,
            items = {
                1937, -- Buzz Saw
                2169, -- Buzzer Blade
                285292, -- Dull Sawblade
            },
        },
        {
            name = "Sneed",
            npcID = 643,
            displayID = 7125,
            items = {
                5194, -- Taskmaster Axe
                5195, -- Gold-flecked Gloves
                273293, -- Bandsaw Wristbands
                273092, -- Blueprint: Repair Bot
            },
        },
        {
            name = "Gilnid",
            npcID = 1763,
            displayID = 7124,
            items = {
                1156, -- Lavishly Jeweled Ring
                5199, -- Smelting Pants
                273297, -- Goblin Hammer
            },
        },
        {
            name = "Mr. Smite",
            npcID = 646,
            displayID = 2026,
            items = {
                7230, -- Smite's Mighty Hammer
                5192, -- Thief's Blade
                5196, -- Smite's Reaver
                284715, -- First Mate Band
            },
        },
        {
            name = "Captain Greenskin",
            npcID = 647,
            displayID = 7113,
            items = {
                5201, -- Emberstone Staff
                10403, -- Blackened Defias Belt
                5200, -- Impaling Harpoon
            },
        },
        {
            name = "Edwin VanCleef",
            npcID = 639,
            displayID = 2029,
            items = {
                5193, -- Cape of the Brotherhood
                5202, -- Corsair's Overshirt
                10399, -- Blackened Defias Armor
                5191, -- Cruel Barb
            },
        },
        {
            name = "Cookie",
            npcID = 645,
            displayID = 1305,
            items = {
                5198, -- Cookie's Stirring Rod
                5197, -- Cookie's Tenderizer
                273298, -- Lookie's Spyglass
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "wc",
    name = "Wailing Caverns",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Lord Cobrahn",
            npcID = 3669,
            displayID = 4213,
            items = {
                6460, -- Cobrahn's Grasp
                10410, -- Leggings of the Fang
                6465, -- Robe of the Moccasin
            },
        },
        {
            name = "Lady Anacondra",
            npcID = 3671,
            displayID = 4313,
            items = {
                10412, -- Belt of the Fang
                5404, -- Serpent's Shoulders
                6446, -- Snakeskin Bag
                273088, -- Snake Eye Kaleidoscope
            },
        },
        {
            name = "Kresh",
            npcID = 3653,
            displayID = 5126,
            items = {
                13245, -- Kresh's Back
                6447, -- Worn Turtle Shell Shield
                273084, -- Cloak of Hermitic Bliss
            },
        },
        {
            name = "Lord Pythas",
            npcID = 3670,
            displayID = 4214,
            items = {
                6472, -- Stinging Viper
                6473, -- Armor of the Fang
                273089, -- Slither Cord
            },
        },
        {
            name = "Skum",
            npcID = 3674,
            displayID = 4203,
            items = {
                6449, -- Glowing Lizardscale Cloak
                6448, -- Tail Spike
                273137, -- Skum's Bucket
            },
        },
        {
            name = "Lord Serpentis",
            npcID = 3673,
            displayID = 4215,
            items = {
                6469, -- Venomstrike
                5970, -- Serpent Gloves
                10411, -- Footpads of the Fang
                6459, -- Savage Trodders
            },
        },
        {
            name = "Verdan the Everliving",
            npcID = 5775,
            displayID = 4256,
            items = {
                6630, -- Seedcloud Buckler
                6631, -- Living Root
                6629, -- Sporid Cape
            },
        },
        {
            name = "Mutanus the Devourer",
            npcID = 3654,
            displayID = 4088,
            items = {
                6461, -- Slime-encrusted Pads
                6627, -- Mutant Scale Breastplate
                6463, -- Deep Fathom Ring
            },
        },
        {
            name = "Deviate Faerie Dragon",
            npcID = 5912,
            displayID = 1267,
            items = {
                5243, -- Firebelcher
                6632, -- Feyscale Cloak
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "sfk",
    name = "Shadowfang Keep",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Rethilgore",
            npcID = 3914,
            displayID = 524,
            items = {
                5254, -- Rugged Spaulders
                273457, -- Sorcerer Collar
                273456, -- Cell Keeper's Claws
            },
        },
        {
            name = "Fel Steed / Shadow Charger",
            npcID = 3864,
            displayID = 1951,
            items = {
                6341, -- Eerie Stable Lantern
                932, -- Fel Steed Saddlebags
            },
        },
        {
            name = "Razorclaw the Butcher",
            npcID = 3886,
            displayID = 524,
            items = {
                1292, -- Butcher's Cleaver
                6226, -- Bloody Apron
                6633, -- Butcher's Slicer
            },
        },
        {
            name = "Baron Silverlaine",
            npcID = 3887,
            displayID = 3222,
            items = {
                6321, -- Silverlaine's Family Seal
                6323, -- Baron's Scepter
                273637, -- Blade of Silverlaine
            },
        },
        {
            name = "Commander Springvale",
            npcID = 4278,
            displayID = 3223,
            items = {
                6320, -- Commander's Crest
                3191, -- Arced War Axe
                273643, -- Worgenbane Talisman
            },
        },
        {
            name = "Odo the Blindwatcher",
            npcID = 4279,
            displayID = 522,
            items = {
                6318, -- Odo's Ley Staff
                6319, -- Girdle of the Blindwatcher
                273645, -- Blindwatcher's Sight
            },
        },
        {
            name = "Deathsworn Captain",
            npcID = 3872,
            displayID = 3224,
            items = {
                6642, -- Phantom Armor
                6641, -- Haunting Blade
            },
        },
        {
            name = "Arugal's Voidwalker",
            npcID = 4627,
            displayID = 1131,
            items = {
                5943, -- Rift Bracers
            },
        },
        {
            name = "Fenrus the Devourer",
            npcID = 4274,
            displayID = 2352,
            items = {
                6340, -- Fenrus' Hide
                3230, -- Black Wolf Bracers
                273646, -- Half-Eaten Boots
            },
        },
        {
            name = "Wolf Master Nandos",
            npcID = 3927,
            displayID = 11179,
            items = {
                3748, -- Feline Mantle
                6314, -- Wolfmaster Cape
            },
        },
        {
            name = "Archmage Arugal",
            npcID = 4275,
            displayID = 2353,
            items = {
                6324, -- Robes of Arugal
                6392, -- Belt of Arugal
                6220, -- Meteor Shard
            },
        },
    },
})

ns.LootData:RegisterStaticInstance({
    key = "bfd",
    name = "Blackfathom Deeps",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Ghamoo-ra",
            npcID = 4887,
            displayID = 5027,
            items = {
                6907, -- Tortoise Armor
                6908, -- Ghamoo-ra's Bind
                273839, -- Spiked Shell Band
            },
        },
        {
            name = "Lady Sarevess",
            npcID = 4831,
            displayID = 4979,
            items = {
                888, -- Naga Battle Gloves
                3078, -- Naga Heartpiercer
                11121, -- Darkwater Talwar
                252798, -- Pattern: Brawler's Leather Hood
            },
        },
        {
            name = "Gelihast",
            npcID = 6243,
            displayID = 20501,
            items = {
                6906, -- Algae Fists
                6905, -- Reef Axe
            },
        },
        {
            name = "Lorgus Jett",
            npcID = 12902,
            displayID = 12822,
            items = {
                273843, -- Fallenroot Longbow
            },
        },
        {
            name = "Old Serra'kis",
            npcID = 4830,
            displayID = 1816,
            items = {
                6901, -- Glowing Thresher Cape
                6904, -- Bite of Serra'kis
                6902, -- Bands of Serra'kis
            },
        },
        {
            name = "Twilight Lord Kelris",
            npcID = 4832,
            displayID = 4939,
            items = {
                1155, -- Rod of the Sleepwalker
                6903, -- Gaze Dreamer Pants
                273846, -- Twilight Lord Girdle
            },
        },
        {
            name = "Aku'mai",
            npcID = 4829,
            displayID = 2837,
            items = {
                6911, -- Moss Cinch
                6910, -- Leech Pants
                6909, -- Strike of the Hydra
            },
        },
    },
})
