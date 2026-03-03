---@class Addon
local addon = select(2, ...)

addon.locale.register('zhTW', {
    -- filter menu
    ['SHOW_EXTRA_SETS'] = '顯示額外套裝',
    ['SHOW_EXTRA_SETS_TOOLTIP'] = '顯示所有你可以使用的套裝，不僅限於本職業套裝。',
    ['SHOW_EXTRA_SETS_SUPPRESSED'] = '已被PvE/PvP篩選抑制',
    ['ONLY_FAVORITES'] = '僅顯示收藏',
    ['INCLUDE_FAVORITE_VARIANTS'] = '包含收藏的變體',
    ['HIDE_ITEMS_NOT_IN_SET'] = '隱藏套裝外物品',
    ['HIDE_ITEMS_NOT_IN_SET_TOOLTIP'] = '套用套裝時，隱藏其他部位。',
    ['MAX_MISSING_PIECES'] = '最大缺失件數',
    ['IGNORED_SLOTS'] = '忽略部位',
    ['IGNORED_SLOTS_TOOLTIP'] = '這些部位不計入最大缺失件數。',
    ['SKIPPED_SLOTS'] = '跳過部位',
    ['SKIPPED_SLOTS_TOOLTIP'] = '這些部位永遠不會被改變。',
    ['HIDDEN_SLOTS'] = '隱藏部位',
    ['HIDDEN_SLOTS_TOOLTIP'] = '這些部位始終隱藏（並且也不計入缺失）。',
    ['USE_CHARACTER_PROFILE'] = '使用角色設定檔',
    ['USE_CHARACTER_PROFILE_TOOLTIP'] = '為每個角色單獨儲存忽略、跳過和隱藏的部位設定。',
    ['RELOAD_SETS'] = '重新載入套裝',
    ['RESET'] = '重置',

    -- sets tab tooltip
    ['MISSING_SLOTS'] = '（缺少：%s）',
    ['SET_ID'] = '（套裝 ID：%d）',
    ['AND_MORE'] = ' 等另外 %d 件',
})
