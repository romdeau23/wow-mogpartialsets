local _, addon = ...
local const = addon.namespace('const')

-- classId => mask
-- https://warcraft.wiki.gg/wiki/ClassId
const.classMasks = {
    [1] = 2 ^ (1 - 1), -- WARRIOR
    [2] = 2 ^ (2 - 1), -- PALADIN
    [3] = 2 ^ (3 - 1), -- HUNTER
    [4] = 2 ^ (4 - 1), -- ROGUE
    [5] = 2 ^ (5 - 1), -- PRIEST
    [6] = 2 ^ (6 - 1), -- DEATHKNIGHT
    [7] = 2 ^ (7 - 1), -- SHAMAN
    [8] = 2 ^ (8 - 1), -- MAGE
    [9] = 2 ^ (9 - 1), -- WARLOCK
    [10] = 2 ^ (10 - 1), -- MONK
    [11] = 2 ^ (11 - 1), -- DRUID
    [12] = 2 ^ (12 - 1), -- DEMONHUNTER
    [13] = 2 ^ (13 - 1), -- EVOKER
}

-- classId => mask
const.armorTypeClassMasks = {
    -- cloth
    [5] = bit.bor(const.classMasks[5], const.classMasks[8], const.classMasks[9]), -- PRIEST
    [8] = bit.bor(const.classMasks[5], const.classMasks[8], const.classMasks[9]), -- MAGE
    [9] = bit.bor(const.classMasks[5], const.classMasks[8], const.classMasks[9]), -- WARLOCK

    -- leather
    [4] = bit.bor(const.classMasks[4], const.classMasks[10], const.classMasks[11], const.classMasks[12]), -- ROGUE
    [10] = bit.bor(const.classMasks[4], const.classMasks[10], const.classMasks[11], const.classMasks[12]), -- MONK
    [11] = bit.bor(const.classMasks[4], const.classMasks[10], const.classMasks[11], const.classMasks[12]), -- DRUID
    [12] = bit.bor(const.classMasks[4], const.classMasks[10], const.classMasks[11], const.classMasks[12]), -- DEMONHUNTER

    -- mail
    [3] = bit.bor(const.classMasks[3], const.classMasks[7], const.classMasks[13]), -- HUNTER
    [7] = bit.bor(const.classMasks[3], const.classMasks[7], const.classMasks[13]), -- SHAMAN
    [13] = bit.bor(const.classMasks[3], const.classMasks[7], const.classMasks[13]), -- EVOKER

    -- plate
    [1] = bit.bor(const.classMasks[1], const.classMasks[2], const.classMasks[6]), -- WARRIOR
    [2] = bit.bor(const.classMasks[1], const.classMasks[2], const.classMasks[6]), -- PALADIN
    [6] = bit.bor(const.classMasks[1], const.classMasks[2], const.classMasks[6]), -- DEATHKNIGHT
}

-- slot => itemId
const.hiddenItemMap = {
    [INVSLOT_HEAD] = 134110,
    [INVSLOT_SHOULDER] = 134112,
    [INVSLOT_BACK] = 134111,
    [INVSLOT_CHEST] = 168659,
    [INVSLOT_BODY] = 142503,
    [INVSLOT_TABARD] = 142504,
    [INVSLOT_WRIST] = 168665,
    [INVSLOT_HAND] = 158329,
    [INVSLOT_WAIST] = 143539,
    [INVSLOT_LEGS] = 216696,
    [INVSLOT_FEET] = 168664,
}

-- slot => label
const.slotLabelMap = {
    [INVSLOT_HEAD] = HEADSLOT,
    [INVSLOT_SHOULDER] = SHOULDERSLOT,
    [INVSLOT_BACK] = BACKSLOT,
    [INVSLOT_CHEST] = CHESTSLOT,
    [INVSLOT_WRIST] = WRISTSLOT,
    [INVSLOT_HAND] = HANDSSLOT,
    [INVSLOT_WAIST] = WAISTSLOT,
    [INVSLOT_LEGS] = LEGSSLOT,
    [INVSLOT_FEET] = FEETSLOT,
}
