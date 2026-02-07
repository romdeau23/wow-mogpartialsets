---@class Addon
local addon = select(2, ...)
---@class UI.FilterModule
local filter, private = addon.module('ui', 'filter'), {}
---@type ConfigModule
local config = addon.namespace('config')
local setSlotOptions = {
    INVSLOT_HEAD, INVSLOT_SHOULDER, INVSLOT_BACK, INVSLOT_CHEST,
    INVSLOT_TABARD, INVSLOT_WRIST, INVSLOT_HAND, INVSLOT_WAIST,
    INVSLOT_LEGS, INVSLOT_FEET,
}
local armorSlotOptions = {
    INVSLOT_HEAD, INVSLOT_SHOULDER, INVSLOT_BACK, INVSLOT_CHEST,
    INVSLOT_TABARD, INVSLOT_BODY, INVSLOT_WRIST, INVSLOT_HAND,
    INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET,
}
local hooked = false

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

    local function getOptionTooltipFn(title, text)
        return function (tooltip)
            tooltip:SetOwner(tooltip:GetOwner(), 'ANCHOR_LEFT')
            GameTooltip_SetTitle(tooltip, title)
            GameTooltip_AddNormalLine(tooltip, text)
        end
    end

    filterButton:SetupMenu(function(dropdown, rootDescription)
        originalGenerator(dropdown, rootDescription)

        -- title
        rootDescription:CreateDivider()
        rootDescription:CreateTitle('MogPartialSets')

        -- show extra sets
        local showExtraSetsCheckbox = rootDescription:CreateCheckbox(
            'Show extra sets',
            function () return config.showExtraSets() end,
            function () config.setShowExtraSets(not config.showExtraSets()) end
        )

        local function updateShowExtraSetsCheckbox()
            showExtraSetsCheckbox:SetEnabled(not addon.ui.setsTab.isPveOrPvpFiltered())
        end

        updateShowExtraSetsCheckbox()

        for _, desc in rootDescription:EnumerateElementDescriptions() do
            local data = desc:GetData()

            if data == LE_TRANSMOG_SET_FILTER_PVE or data == LE_TRANSMOG_SET_FILTER_PVP then
                -- update enabled state when PvE/PvP filter changes
                desc:HookResponder(updateShowExtraSetsCheckbox)
            end
        end

        local enabledExtraSetsTooltipFn = getOptionTooltipFn('Show extra sets', 'Show all the sets you can use, not just your class sets.')

        showExtraSetsCheckbox:SetTooltip(function(tooltip, elementDescription)
            enabledExtraSetsTooltipFn(tooltip)

            if addon.ui.setsTab.isPveOrPvpFiltered() then
                GameTooltip_AddErrorLine(tooltip, 'Suppressed by PvE/PvP filter')
            end
        end)

        -- only favorites
        rootDescription:CreateCheckbox(
            'Only favorites',
            function () return config.onlyFavorite() end,
            function () config.setOnlyFavorite(not config.onlyFavorite()) end
        )

        -- include favorite variants
        local favoriteVariantsCheckbox = rootDescription:CreateCheckbox(
            'Include favorite variants',
            function () return config.favoriteVariants() end,
            function () config.setFavoriteVariants(not config.favoriteVariants()) end
        )

        favoriteVariantsCheckbox:SetEnabled(function () return config.onlyFavorite() end)

        -- hide items not in set
        local hideItemsNotInSetCheckbox = rootDescription:CreateCheckbox(
            'Hide items not in set',
            function () return config.hideItemsNotInSet() end,
            function () config.setHideItemsNotInSet(not config.hideItemsNotInSet()) end
        )

        hideItemsNotInSetCheckbox:SetTooltip(getOptionTooltipFn('Hide items not in set', 'When applying a set, hide the other slots.'))

        -- max missing pieces
        local maxMissingPiecesButton = rootDescription:CreateButton('Max missing pieces')

        for value = 0, 10 do
            maxMissingPiecesButton:CreateRadio(
                tostring(value),
                function () return config.maxMissingPieces() == value end,
                function ()
                    config.setMaxMissingPieces(value)

                    return MenuResponse.Refresh
                end
            )
        end

        -- ignored slots
        local ignoredSlotsButton = rootDescription:CreateButton('Ignored slots')

        ignoredSlotsButton:SetTooltip(getOptionTooltipFn('Ignored slots', 'These slots don\'t count towards max missing pieces.'))

        for _, invSlotId in ipairs(setSlotOptions) do
            ignoredSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.ignoredSlots.has(invSlotId) end,
                function () config.ignoredSlots.set(invSlotId, not config.ignoredSlots.has(invSlotId)) end
            )
        end

        ignoredSlotsButton:CreateButton('Reset', function ()
            config.ignoredSlots.clear()

            return MenuResponse.Refresh
        end)

        -- skipped slots
        local skippedSlotsButton = rootDescription:CreateButton('Skipped slots')

        skippedSlotsButton:SetTooltip(getOptionTooltipFn('Skipped slots', 'These slots are never changed.'))

        for _, invSlotId in ipairs(armorSlotOptions) do
            skippedSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.skippedSlots.has(invSlotId) end,
                function () config.skippedSlots.set(invSlotId, not config.skippedSlots.has(invSlotId)) end
            )
        end

        skippedSlotsButton:CreateButton('Reset', function ()
            config.skippedSlots.clear()

            return MenuResponse.Refresh
        end)

        -- hidden slots
        local hiddenSlotsButton = rootDescription:CreateButton('Hidden slots')

        hiddenSlotsButton:SetTooltip(getOptionTooltipFn('Hidden slots', 'These slots are always hidden (and also don\'t count as missing).'))

        for _, invSlotId in ipairs(setSlotOptions) do
            hiddenSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.hiddenSlots.has(invSlotId) end,
                function () config.hiddenSlots.set(invSlotId, not config.hiddenSlots.has(invSlotId)) end
            )
        end

        hiddenSlotsButton:CreateButton('Reset', function ()
            config.hiddenSlots.clear()

            return MenuResponse.Refresh
        end)

        rootDescription:CreateDivider()

        -- use character profile
        local useCharacterProfileCheckbox = rootDescription:CreateCheckbox(
            'Use character profile',
            function () return config.characterProfileEnabled() end,
            function () config.setCharacterProfileEnabled(not config.characterProfileEnabled()) end
        )

        useCharacterProfileCheckbox:SetTooltip(getOptionTooltipFn('Use character profile', 'Save the ignored, skipped and hidden slots per-character.'))

        -- reload button
        rootDescription:CreateButton('Reload sets', function ()
            addon.setLoader.clearSetData()
            addon.ui.setsTab.refreshIfVisible()
        end)
    end)
end
