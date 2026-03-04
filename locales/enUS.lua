---@class Addon
local addon = select(2, ...)

addon.locale.register('enUS', {
    -- filter menu
    ['SHOW_EXTRA_SETS'] = 'Show extra sets',
    ['SHOW_EXTRA_SETS_TOOLTIP'] = 'Show all the sets you can use, not just your class sets.',
    ['SHOW_EXTRA_SETS_SUPPRESSED'] = 'Suppressed by PvE/PvP filter',
    ['ONLY_FAVORITES'] = 'Only favorites',
    ['INCLUDE_FAVORITE_VARIANTS'] = 'Include favorite variants',
    ['HIDE_ITEMS_NOT_IN_SET'] = 'Hide items not in set',
    ['HIDE_ITEMS_NOT_IN_SET_TOOLTIP'] = 'When applying a set, hide the other slots.',
    ['MAX_MISSING_PIECES'] = 'Max missing pieces',
    ['IGNORED_SLOTS'] = 'Ignored slots',
    ['IGNORED_SLOTS_TOOLTIP'] = 'These slots don\'t count towards max missing pieces.',
    ['SKIPPED_SLOTS'] = 'Skipped slots',
    ['SKIPPED_SLOTS_TOOLTIP'] = 'These slots are never changed.',
    ['HIDDEN_SLOTS'] = 'Hidden slots',
    ['HIDDEN_SLOTS_TOOLTIP'] = 'These slots are always hidden (and also don\'t count as missing).',
    ['USE_CHARACTER_PROFILE'] = 'Use character profile',
    ['USE_CHARACTER_PROFILE_TOOLTIP'] = 'Save the ignored, skipped and hidden slots per-character.',
    ['RELOAD_SETS'] = 'Reload sets',
    ['RESET'] = 'Reset',

    -- sets tab tooltip
    ['MISSING_SLOTS'] = '(Missing: %s)',
    ['SET_ID'] = '(Set ID: %d)',
    ['AND_MORE'] = ' and %d more',
})
