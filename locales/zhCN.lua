---@class Addon
local addon = select(2, ...)

addon.locale.register('zhCN', {
    -- filter menu
    ['SHOW_EXTRA_SETS'] = '显示额外套装',
    ['SHOW_EXTRA_SETS_TOOLTIP'] = '显示所有你可以使用的套装，不仅限于本职业套装。',
    ['SHOW_EXTRA_SETS_SUPPRESSED'] = '已被PvE/PvP筛选抑制',
    ['ONLY_FAVORITES'] = '仅显示收藏',
    ['INCLUDE_FAVORITE_VARIANTS'] = '包含收藏的变体',
    ['HIDE_ITEMS_NOT_IN_SET'] = '隐藏套装外物品',
    ['HIDE_ITEMS_NOT_IN_SET_TOOLTIP'] = '应用套装时，隐藏其他部位。',
    ['MAX_MISSING_PIECES'] = '最大缺失件数',
    ['IGNORED_SLOTS'] = '忽略部位',
    ['IGNORED_SLOTS_TOOLTIP'] = '这些部位不计入最大缺失件数。',
    ['SKIPPED_SLOTS'] = '跳过部位',
    ['SKIPPED_SLOTS_TOOLTIP'] = '这些部位永远不会被改变。',
    ['HIDDEN_SLOTS'] = '隐藏部位',
    ['HIDDEN_SLOTS_TOOLTIP'] = '这些部位始终隐藏（并且也不计入缺失）。',
    ['USE_CHARACTER_PROFILE'] = '使用角色配置',
    ['USE_CHARACTER_PROFILE_TOOLTIP'] = '为每个角色单独保存忽略、跳过和隐藏的部位设置。',
    ['RELOAD_SETS'] = '重新加载套装',
    ['RESET'] = '重置',

    -- sets tab tooltip
    ['MISSING_SLOTS'] = '（缺少：%s）',
    ['SET_ID'] = '（套装 ID：%d）',
    ['AND_MORE'] = ' 等另外 %d 件',
})
