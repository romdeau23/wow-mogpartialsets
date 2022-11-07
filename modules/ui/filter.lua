local _, addon = ...
local filter, private = addon.module('ui', 'filter')

function filter.attach()
    MogPartialSets_FilterButton:SetParent(WardrobeCollectionFrame.SetsTransmogFrame)
    MogPartialSets_FilterButton:SetPoint('LEFT', WardrobeCollectionFrameSearchBox, 'RIGHT', 2, -1)
    MogPartialSets_FilterButton:Show()
end

function filter.updateStates()
    MogPartialSets_Filter.FavoriteVariantsToggle:SetAlpha(addon.config.db.onlyFavorite and 1 or 0.5)
end

function filter.onChange()
    addon.ui.refreshSets(true)
    filter.updateStates()
end

function filter.hide()
    MogPartialSets_Filter:Hide()
end

function filter.onRefreshClicked()
    addon.api.helpers.clearCaches()
    addon.ui.refreshSets(true)
end
