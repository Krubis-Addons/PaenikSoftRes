-- WoW: Forever – Dungeons der Beta-Phase 2 (Update vom 1. Oktober 2026, Stufe 30, Client 1.60.1.70205).
-- Neu: Excavation Site: Wetlands; freigeschaltet: Razorfen Downs, Uldaman; schon zuvor spielbar, hier ergänzt:
-- The Stockade, Gnomeregan, Razorfen Kraul, Scarlet Monastery (vier Flügel).
-- Bosse, Porträt-DisplayIDs und ItemIDs per Skript aus foreverchanges.pro (eingebettete Seitendaten,
-- Stand 2026-10-03); Forever hat den Classic-Loot stark verändert („neu in Forever“). Graue/weiße und
-- Quest-Items ausgelassen, Bosse ohne verteilbaren Loot ebenso; Trash-Loot als Auffüll-Items.
-- Beta-Daten: Blizzard kann Drops noch ändern; unbekannte Items blendet LootData zur Laufzeit aus.
local _, ns = ...

ns.LootData:RegisterStaticInstance({
    key = "stock",
    name = "The Stockade",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Kam Deepfury",
            displayID = 825,
            items = {
                2280, -- Kam's Walking Stick
                273808, -- Bridgebreaker Bindings (neu in Forever)
            },
        },
        {
            name = "Bruegal Ironknuckle",
            displayID = 2142,
            rare = true,
            items = {
                3228, -- Jimmied Handcuffs
                2941, -- Prison Shank
                2942, -- Iron Knuckles
            },
        },
        {
            name = "Targorr the Dread",
            items = {
                273804, -- Executioner Mantle (neu in Forever)
                273805, -- Blackrock Harness (neu in Forever)
                273806, -- Dark Horde Band (neu in Forever)
                273820, -- Nightskulker Ring (neu in Forever)
            },
        },
        {
            name = "Hamhock",
            items = {
                273809, -- Hamhock's Cleaver (neu in Forever)
                273810, -- Ogre Grips (neu in Forever)
                273811, -- Repurposed Rack (neu in Forever)
            },
        },
        {
            name = "Bazil Thredd",
            items = {
                273824, -- Defias Jailbreakers (neu in Forever)
                273825, -- Red Wool Cloak (neu in Forever)
                273827, -- Debt Collector (neu in Forever)
                273829, -- Concealed Hand Crossbow (neu in Forever)
            },
        },
    },
    filler = {
        1076, -- Defias Renegade Ring
        274092, -- Sharpened Cutlery
    },
})

ns.LootData:RegisterStaticInstance({
    key = "gnome",
    name = "Gnomeregan",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Grubbis",
            displayID = 6533,
            items = {
                9445, -- Grubbis Paws
            },
        },
        {
            name = "Viscous Fallout",
            displayID = 5497,
            items = {
                9454, -- Acidic Walkers
                9453, -- Toxic Revenger
                9452, -- Hydrocane
            },
        },
        {
            name = "Electrocutioner 6000",
            displayID = 6915,
            items = {
                9447, -- Electrocutioner Lagnut
                9446, -- Electrocutioner Leg
                9448, -- Spidertank Oilrag
            },
        },
        {
            name = "Crowd Pummeler 9-60",
            displayID = 6774,
            items = {
                9449, -- Manual Crowd Pummeler
                9450, -- Gnomebot Operating Boots
                274068, -- Thermaplugg Medal of Honor (neu in Forever)
            },
        },
        {
            name = "Dark Iron Ambassador",
            displayID = 6669,
            rare = true,
            items = {
                9455, -- Emissary Cuffs
                9456, -- Glass Shooter
                9457, -- Royal Diplomatic Scepter
            },
        },
        {
            name = "Mekgineer Thermaplugg",
            displayID = 6980,
            items = {
                9492, -- Electromagnetic Gigaflux Reactivator
                9461, -- Charged Gear
                9458, -- Thermaplugg's Central Core
                9459, -- Thermaplugg's Left Arm
                4415, -- Schematic: Craftsman's Monocle
                4413, -- Schematic: Discombobulator Ray
                4411, -- Schematic: Flame Deflector
                11828, -- Schematic: Pet Bombling
            },
        },
    },
    filler = {
        9508, -- Mechbuilder's Overalls
        9491, -- Hotshot Pilot's Gloves
        9509, -- Petrolspill Leggings
        9510, -- Caverndeep Trudgers
        9487, -- Hi-Tech Supergun
        9485, -- Vibroblade
        9488, -- Oscillating Power Hammer
        9486, -- Supercharger Battle Axe
        9490, -- Gizmotron Megachopper
        9489, -- Gyromatic Icemaker
        11827, -- Schematic: Lil' Smoky
        9327, -- Security DELTA Data Access Card
    },
})

ns.LootData:RegisterStaticInstance({
    key = "rfk",
    name = "Razorfen Kraul",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Aggem Thorncurse",
            displayID = 6097,
            items = {
                6681, -- Thornspike
                274158, -- Death Prophet Spine (neu in Forever)
            },
        },
        {
            name = "Death Speaker Jargba",
            displayID = 4644,
            items = {
                2816, -- Death Speaker Scepter
                6685, -- Death Speaker Mantle
                6682, -- Death Speaker Robes
            },
        },
        {
            name = "Roogug",
            displayID = 6110,
            items = {
                274155, -- Geomancer Headdress (neu in Forever)
                274152, -- Roogug's Severed Head (neu in Forever)
            },
        },
        {
            name = "Overlord Ramtusk",
            displayID = 4652,
            items = {
                6687, -- Corpsemaker
                6686, -- Tusken Helm
                274161, -- Quillord Mail Leggings (neu in Forever)
            },
        },
        {
            name = "Razorfen Spearhide",
            displayID = 6078,
            items = {
                6679, -- Armor Piercer
            },
        },
        {
            name = "Agathelos the Raging",
            displayID = 2450,
            items = {
                6691, -- Swinetusk Shank
                6690, -- Ferine Leggings
                274158, -- Death Prophet Spine (neu in Forever)
                274160, -- Quilrager Throwing Axe (neu in Forever)
            },
        },
        {
            name = "Blind Hunter",
            displayID = 4735,
            rare = true,
            items = {
                6695, -- Stygian Bone Amulet
                6697, -- Batwing Mantle
                6696, -- Nightstalker Bow
            },
        },
        {
            name = "Charlga Razorflank",
            displayID = 4642,
            items = {
                6693, -- Agamaggan's Clutch
                6694, -- Heart of Agamaggan
                6692, -- Pronged Reaver
            },
        },
        {
            name = "Earthcaller Halmgar",
            displayID = 6102,
            rare = true,
            items = {
                6689, -- Wind Spirit Staff
                6688, -- Whisperwind Headdress
            },
        },
    },
    filler = {
        2264, -- Mantle of Thieves
        1488, -- Avenger's Armor
        4438, -- Pugilist Bracers
        1978, -- Wolfclaw Gloves
        2039, -- Plains Ring
        1727, -- Sword of Decay
        776, -- Vendetta
        1976, -- Slaghammer
        1975, -- Pysan's Old Greatsword
        2549, -- Staff of the Shade
        6681, -- Thornspike
        6679, -- Armor Piercer
        3569, -- Vicar's Robe
    },
})

ns.LootData:RegisterStaticInstance({
    key = "smgy",
    name = "Scarlet Monastery: Graveyard",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Interrogator Vishas",
            displayID = 2044,
            items = {
                7682, -- Torturing Poker
                7683, -- Bloody Brass Knuckles
            },
        },
        {
            name = "Azshir the Sleepless",
            displayID = 5534,
            rare = true,
            items = {
                7709, -- Blighted Leggings
                7708, -- Necrotic Wand
                7731, -- Ghostshard Talisman
            },
        },
        {
            name = "Fallen Champion",
            displayID = 5230,
            rare = true,
            items = {
                7691, -- Embalmed Shroud
                7690, -- Ebon Vise
                7689, -- Morbid Dawn
            },
        },
        {
            name = "Ironspine",
            displayID = 5231,
            rare = true,
            items = {
                7688, -- Ironspine's Ribcage
                7687, -- Ironspine's Fist
                7686, -- Ironspine's Eye
            },
        },
        {
            name = "Bloodmage Thalnos",
            displayID = 11396,
            items = {
                7685, -- Orb of the Forgotten Seer
                7684, -- Bloodmage Mantle
            },
        },
    },
    filler = {
        5819, -- Sunblaze Coif
        7727, -- Watchman Pauldrons
        7728, -- Beguiler Robes
        7754, -- Harbinger Boots
        10332, -- Scarlet Boots
        2262, -- Mark of Kern
        7787, -- Resplendent Guardian
        7729, -- Chesterfall Musket
        7761, -- Steelclaw Reaver
        7752, -- Dreamslayer
        8226, -- The Butcher
        7786, -- Headsplitter
        7753, -- Bloodspiller
        7730, -- Cobalt Crusher
        1992, -- Swampchill Fetish
        5756, -- Sliverblade
        7736, -- Fight Club
        7755, -- Flintrock Shoulders
        7757, -- Windweaver Staff
        7758, -- Ruthless Shiv
        7759, -- Archon Chestpiece
        7760, -- Warchief Kilt
        8225, -- Tainted Pierce
        10328, -- Scarlet Chestpiece
        10329, -- Scarlet Belt
        10330, -- Scarlet Leggings
        10331, -- Scarlet Gauntlets
        10333, -- Scarlet Wristguards
    },
})

ns.LootData:RegisterStaticInstance({
    key = "smlib",
    name = "Scarlet Monastery: Library",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Houndmaster Loksey",
            displayID = 2040,
            items = {
                7710, -- Loksey's Training Stick
                7756, -- Dog Training Gloves
                3456, -- Dog Whistle
            },
        },
        {
            name = "Arcanist Doan",
            displayID = 5266,
            items = {
                7714, -- Hypnotic Blade
                7713, -- Illusionary Rod
                7712, -- Mantle of Doan
                7711, -- Robe of Doan
            },
        },
        {
            name = "Doan's Strongbox",
            items = {
                7146, -- The Scarlet Key
            },
        },
    },
    filler = {
        5819, -- Sunblaze Coif
        7755, -- Flintrock Shoulders
        7727, -- Watchman Pauldrons
        7728, -- Beguiler Robes
        7759, -- Archon Chestpiece
        7760, -- Warchief Kilt
        7754, -- Harbinger Boots
        10332, -- Scarlet Boots
        1992, -- Swampchill Fetish
        2262, -- Mark of Kern
        7787, -- Resplendent Guardian
        7729, -- Chesterfall Musket
        7761, -- Steelclaw Reaver
        7752, -- Dreamslayer
        8226, -- The Butcher
        7786, -- Headsplitter
        5756, -- Sliverblade
        7736, -- Fight Club
        8225, -- Tainted Pierce
        7753, -- Bloodspiller
        7730, -- Cobalt Crusher
        7758, -- Ruthless Shiv
        7757, -- Windweaver Staff
        10328, -- Scarlet Chestpiece
        10329, -- Scarlet Belt
        10330, -- Scarlet Leggings
        10331, -- Scarlet Gauntlets
        10333, -- Scarlet Wristguards
    },
})

ns.LootData:RegisterStaticInstance({
    key = "smarm",
    name = "Scarlet Monastery: Armory",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Herod",
            displayID = 2041,
            items = {
                7719, -- Raging Berserker's Helm
                7718, -- Herod's Shoulder
                10330, -- Scarlet Leggings
                7717, -- Ravager
            },
        },
    },
    filler = {
        5819, -- Sunblaze Coif
        7755, -- Flintrock Shoulders
        7727, -- Watchman Pauldrons
        7728, -- Beguiler Robes
        7759, -- Archon Chestpiece
        7754, -- Harbinger Boots
        10332, -- Scarlet Boots
        1992, -- Swampchill Fetish
        2262, -- Mark of Kern
        7787, -- Resplendent Guardian
        7729, -- Chesterfall Musket
        7761, -- Steelclaw Reaver
        7752, -- Dreamslayer
        8226, -- The Butcher
        7786, -- Headsplitter
        5756, -- Sliverblade
        7736, -- Fight Club
        8225, -- Tainted Pierce
        7753, -- Bloodspiller
        7730, -- Cobalt Crusher
        7757, -- Windweaver Staff
        10333, -- Scarlet Wristguards
        10329, -- Scarlet Belt
        7758, -- Ruthless Shiv
        7760, -- Warchief Kilt
        10328, -- Scarlet Chestpiece
        10330, -- Scarlet Leggings
        10331, -- Scarlet Gauntlets
    },
})

ns.LootData:RegisterStaticInstance({
    key = "smcath",
    name = "Scarlet Monastery: Cathedral",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "High Inquisitor Fairbanks",
            displayID = 2605,
            items = {
                19507, -- Inquisitor's Shawl
                19508, -- Branded Leather Bracers
                19509, -- Dusty Mail Boots
            },
        },
        {
            name = "Scarlet Commander Mograine",
            displayID = 2042,
            items = {
                7724, -- Gauntlets of Divinity
                10330, -- Scarlet Leggings
                7726, -- Aegis of the Scarlet Commander
                7723, -- Mograine's Might
            },
        },
        {
            name = "High Inquisitor Whitemane",
            displayID = 2043,
            items = {
                7720, -- Whitemane's Chapeau
                7722, -- Triune Amulet
                7721, -- Hand of Righteousness
            },
        },
    },
    filler = {
        5819, -- Sunblaze Coif
        7755, -- Flintrock Shoulders
        7727, -- Watchman Pauldrons
        7728, -- Beguiler Robes
        7759, -- Archon Chestpiece
        7760, -- Warchief Kilt
        7754, -- Harbinger Boots
        10332, -- Scarlet Boots
        1992, -- Swampchill Fetish
        2262, -- Mark of Kern
        7787, -- Resplendent Guardian
        7729, -- Chesterfall Musket
        7761, -- Steelclaw Reaver
        7752, -- Dreamslayer
        8226, -- The Butcher
        7786, -- Headsplitter
        5756, -- Sliverblade
        7736, -- Fight Club
        8225, -- Tainted Pierce
        7753, -- Bloodspiller
        7730, -- Cobalt Crusher
        7758, -- Ruthless Shiv
        7757, -- Windweaver Staff
        10328, -- Scarlet Chestpiece
        10331, -- Scarlet Gauntlets
        10329, -- Scarlet Belt
        10330, -- Scarlet Leggings
        10333, -- Scarlet Wristguards
    },
})

ns.LootData:RegisterStaticInstance({
    key = "rfd",
    name = "Razorfen Downs",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Tuten'kash",
            displayID = 7845,
            items = {
                10776, -- Silky Spider Cape
                10775, -- Carapace of Tuten'kash
                10777, -- Arachnid Gloves
            },
        },
        {
            name = "Mordresh Fire Eye",
            displayID = 8055,
            items = {
                10769, -- Glowing Eye of Mordresh
                10771, -- Deathmage Sash
                10770, -- Mordresh's Lifeless Skull
            },
        },
        {
            name = "Glutton",
            displayID = 7864,
            items = {
                10774, -- Fleshhide Shoulders
                10772, -- Glutton's Cleaver
            },
        },
        {
            name = "Ragglesnout",
            displayID = 11382,
            rare = true,
            items = {
                10768, -- Boar Champion's Belt
                10767, -- Savage Boar's Guard
                10758, -- X'caliboar
            },
        },
        {
            name = "Amnennar the Coldbringer",
            displayID = 7971,
            items = {
                10763, -- Icemetal Barbute
                10762, -- Robes of the Lich
                10764, -- Deathchill Armor
                10761, -- Coldrage Dagger
                10765, -- Bonefingers
            },
        },
        {
            name = "Plaguemaw the Rotting",
            displayID = 6124,
            items = {
                10766, -- Plaguerot Sprig
                10760, -- Swine Fists
            },
        },
    },
    filler = {
        10574, -- Corpseshroud
        10581, -- Death's Head Vestment
        10583, -- Quillward Harness
        10584, -- Stormgale Fists
        10578, -- Thoughtcast Boots
        10582, -- Briar Tredders
        10572, -- Freezing Shard
        10567, -- Quillshooter
        10571, -- Ebony Boneclub
        10570, -- Manslayer
        10573, -- Boneslasher
    },
})

ns.LootData:RegisterStaticInstance({
    key = "ulda",
    name = "Uldaman",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Eric \"The Swift\"",
            displayID = 5708,
            items = {
                9394, -- Horned Viking Helmet
                9398, -- Worn Running Boots
            },
        },
        {
            name = "Baelog",
            displayID = 5710,
            items = {
                9401, -- Nordic Longshank
                9399, -- Precision Arrow
            },
        },
        {
            name = "Olaf",
            displayID = 5709,
            items = {
                9404, -- Olaf's All Purpose Shield
            },
        },
        {
            name = "Revelosh",
            displayID = 5945,
            items = {
                9389, -- Revelosh's Spaulders
                9388, -- Revelosh's Armguards
                9390, -- Revelosh's Gloves
                9387, -- Revelosh's Boots
            },
        },
        {
            name = "Ironaya",
            displayID = 6089,
            items = {
                9409, -- Ironaya's Bracers
                9407, -- Stoneweaver Leggings
                9408, -- Ironshod Bludgeon
            },
        },
        {
            name = "Ancient Stone Keeper",
            displayID = 10798,
            items = {
                9410, -- Cragfists
                9411, -- Rockshard Pauldrons
            },
        },
        {
            name = "Galgann Firehammer",
            displayID = 6059,
            items = {
                11310, -- Flameseer Mantle
                9412, -- Galgann's Fireblaster
                11311, -- Emberscale Cape
                9419, -- Galgann's Firehammer
            },
        },
        {
            name = "Grimlok",
            displayID = 11165,
            items = {
                9415, -- Grimlok's Tribal Vestments
                9416, -- Grimlok's Charge
                9414, -- Oilskin Leggings
            },
        },
        {
            name = "Archaedas",
            displayID = 5988,
            items = {
                11118, -- Archaedic Stone
                9413, -- The Rockpounder
                9418, -- Stoneslayer
            },
        },
    },
    filler = {
        9431, -- Papal Fez
        9429, -- Miner's Hat of the Deep
        9420, -- Adventurer's Pith Helmet
        9430, -- Spaulders of a Lost Age
        9397, -- Energy Cloak
        9406, -- Spirewind Fetter
        9428, -- Unearthed Bands
        9432, -- Skullplate Bracers
        9396, -- Legguards of the Vault
        9393, -- Beacon of Hope
        7666, -- Shattered Necklace
        9381, -- Earthen Rod
        9426, -- Monolithic Bow
        9422, -- Shadowforge Bushmaster
        9465, -- Digmaster 5000
        9384, -- Stonevault Shiv
        9386, -- Excavator's Brand
        9427, -- Stonevault Bonebreaker
        9392, -- Annealed Blade
        9424, -- Ginn-su Sword
        9383, -- Obsidian Cleaver
        9425, -- Pendulum of Doom
        9423, -- The Jackhammer
        9391, -- The Shoveler
    },
})

ns.LootData:RegisterStaticInstance({
    key = "exc",
    name = "Excavation Site: Wetlands",
    isRaid = false,
    maxPlayers = 5,
    encounters = {
        {
            name = "Saltspine",
            displayID = 144209,
            items = {
                273022, -- Supple Bellyskin Leggings (neu in Forever)
                273023, -- Saltscale Girdle (neu in Forever)
                273024, -- Glinteye Slippers (neu in Forever)
            },
        },
        {
            name = "Shadetooth",
            displayID = 144210,
            items = {
                273027, -- Raptor's Gaze (neu in Forever)
                273025, -- Raptorclaw Greaves (neu in Forever)
                273026, -- Garb of Florid Feathers (neu in Forever)
                273106, -- Blueprint: Greenhouse (neu in Forever)
            },
        },
        {
            name = "Relic Guardian",
            displayID = 144224,
            items = {
                273028, -- Reliquary Mantle (neu in Forever)
                273029, -- Golemsight Long Gun (neu in Forever)
                273030, -- Ring of Power Regulation (neu in Forever)
            },
        },
    },
})

