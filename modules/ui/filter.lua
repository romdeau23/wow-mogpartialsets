local _, addon = ...
local filter, private = addon.module('ui', 'filter'), {}
local hooked = false
local slotOptions = {
    INVSLOT_HEAD, INVSLOT_SHOULDER, INVSLOT_BACK,
    INVSLOT_CHEST, INVSLOT_WRIST, INVSLOT_HAND,
    INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET,
}

function filter.hook(setsFrame)
    if hooked then
        return
    end

    local filterButton = setsFrame.FilterButton

    if not filterButton.menuGenerator then
        hooksecurefunc(setsFrame, 'InitFilterButton', function () private.setupButton(filterButton) end)
    else
        private.setupButton(filterButton)
    end

    hooked = true
end

function private.setupButton(filterButton)
    local originalGenerator = filterButton.menuGenerator

    filterButton:SetupMenu(function(dropdown, rootDescription)
        originalGenerator(dropdown, rootDescription)

        -- title
        rootDescription:CreateDivider()
        rootDescription:CreateTitle('MogPartialSets')

        -- show extra sets
        local extraSets = rootDescription:CreateCheckbox(
            'Show extra sets',
            function () return addon.config.db.showExtraSets end,
            function () private.toggleConfigOption('showExtraSets') end
        )

        extraSets:SetEnabled(function () return not addon.ui.sets.isPveOrPveFiltered() end)

        extraSets:SetTooltip(function(tooltip, elementDescription)
            if not addon.ui.sets.isPveOrPveFiltered() then
                return
            end

            GameTooltip_AddNormalLine(tooltip, 'Unavailable due to PvP/PvE filter')
            local line = _G[tooltip:GetName() .. 'TextLeft' .. tooltip:NumLines()]

            if line then
                line:SetFontObject(GameFontDisableSmall)
                line:SetTextColor(0.5, 0.5, 0.5)
            end
        end)

        -- only favorites
        rootDescription:CreateCheckbox(
            'Only favorites',
            function () return addon.config.db.onlyFavorite end,
            function () private.toggleConfigOption('onlyFavorite') end
        )

        -- include favorite variants
        local favoriteVariants = rootDescription:CreateCheckbox(
            'Include favorite variants',
            function () return addon.config.db.favoriteVariants end,
            function () private.toggleConfigOption('favoriteVariants') end
        )

        favoriteVariants:SetEnabled(function () return addon.config.db.onlyFavorite end)

        -- use hidden if missing
        rootDescription:CreateCheckbox(
            'Use hidden if missing',
            function () return addon.config.db.useHiddenIfMissing end,
            function () private.toggleConfigOption('useHiddenIfMissing') end
        )

        -- hide items not in set
        rootDescription:CreateCheckbox(
            'Hide items not in set',
            function () return addon.config.db.hideItemsNotInSet end,
            function () private.toggleConfigOption('hideItemsNotInSet') end
        )

        -- max missing pieces
        local maxMissingMenu = rootDescription:CreateButton('Max missing pieces')

        for value = 0, 10 do
            maxMissingMenu:CreateRadio(
                tostring(value),
                function () return addon.config.db.maxMissingPieces == value end,
                function ()
                    addon.config.db.maxMissingPieces = value
                    private.refresh()
                    return MenuResponse.Refresh
                end
            )
        end

        -- ignored slots
        local ignoredMenu = rootDescription:CreateButton('Ignored slots')

        for _, slot in ipairs(slotOptions) do
            ignoredMenu:CreateCheckbox(
                addon.const.slotLabelMap[slot],
                function () return addon.config.isIgnoredSlot(slot) end,
                function ()
                    addon.config.setIgnoredSlot(slot, not addon.config.isIgnoredSlot(slot))
                    private.refresh()
                end
            )
        end

        -- hidden slots
        local hiddenMenu = rootDescription:CreateButton('Hidden slots')

        for _, slot in ipairs(slotOptions) do
            hiddenMenu:CreateCheckbox(
                addon.const.slotLabelMap[slot],
                function () return addon.config.isHiddenSlot(slot) end,
                function ()
                    addon.config.setHiddenSlot(slot, not addon.config.isHiddenSlot(slot))
                    private.refresh()
                end
            )
        end

        -- refresh button
        rootDescription:CreateDivider()
        rootDescription:CreateButton('Refresh set data', function ()
            addon.setLoader.clearCaches()
            addon.sourceLoader.clearCache()
            private.refresh()
        end)
    end)
end

function private.refresh()
    addon.ui.sets.refresh()
end

function private.toggleConfigOption(key)
    addon.config.db[key] = not addon.config.db[key]
    private.refresh()
end
