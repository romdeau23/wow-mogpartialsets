---@class Addon
local addon = select(2, ...)
local filter, private = addon.module(), {}
addon.ui.filter = filter

local L = addon.L
local config = addon.config
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
            L('SHOW_EXTRA_SETS'),
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

        local enabledExtraSetsTooltipFn = getOptionTooltipFn(L('SHOW_EXTRA_SETS'), L('SHOW_EXTRA_SETS_TOOLTIP'))

        showExtraSetsCheckbox:SetTooltip(function(tooltip, elementDescription)
            enabledExtraSetsTooltipFn(tooltip)

            if addon.ui.setsTab.isPveOrPvpFiltered() then
                GameTooltip_AddErrorLine(tooltip, L('SHOW_EXTRA_SETS_SUPPRESSED'))
            end
        end)

        -- only favorites
        rootDescription:CreateCheckbox(
            L('ONLY_FAVORITES'),
            function () return config.onlyFavorite() end,
            function () config.setOnlyFavorite(not config.onlyFavorite()) end
        )

        -- include favorite variants
        local favoriteVariantsCheckbox = rootDescription:CreateCheckbox(
            L('INCLUDE_FAVORITE_VARIANTS'),
            function () return config.favoriteVariants() end,
            function () config.setFavoriteVariants(not config.favoriteVariants()) end
        )

        favoriteVariantsCheckbox:SetEnabled(function () return config.onlyFavorite() end)

        -- hide items not in set
        local hideItemsNotInSetCheckbox = rootDescription:CreateCheckbox(
            L('HIDE_ITEMS_NOT_IN_SET'),
            function () return config.hideItemsNotInSet() end,
            function () config.setHideItemsNotInSet(not config.hideItemsNotInSet()) end
        )

        hideItemsNotInSetCheckbox:SetTooltip(getOptionTooltipFn(L('HIDE_ITEMS_NOT_IN_SET'), L('HIDE_ITEMS_NOT_IN_SET_TOOLTIP')))

        -- max missing pieces
        local maxMissingPiecesButton = rootDescription:CreateButton(L('MAX_MISSING_PIECES'))

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
        local ignoredSlotsButton = rootDescription:CreateButton(L('IGNORED_SLOTS'))

        ignoredSlotsButton:SetTooltip(getOptionTooltipFn(L('IGNORED_SLOTS'), L('IGNORED_SLOTS_TOOLTIP')))

        for _, invSlotId in ipairs(setSlotOptions) do
            ignoredSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.ignoredSlots.has(invSlotId) end,
                function () config.ignoredSlots.set(invSlotId, not config.ignoredSlots.has(invSlotId)) end
            )
        end

        ignoredSlotsButton:CreateButton(L('RESET'), function ()
            config.ignoredSlots.clear()

            return MenuResponse.Refresh
        end)

        -- skipped slots
        local skippedSlotsButton = rootDescription:CreateButton(L('SKIPPED_SLOTS'))

        skippedSlotsButton:SetTooltip(getOptionTooltipFn(L('SKIPPED_SLOTS'), L('SKIPPED_SLOTS_TOOLTIP')))

        for _, invSlotId in ipairs(armorSlotOptions) do
            skippedSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.skippedSlots.has(invSlotId) end,
                function () config.skippedSlots.set(invSlotId, not config.skippedSlots.has(invSlotId)) end
            )
        end

        skippedSlotsButton:CreateButton(L('RESET'), function ()
            config.skippedSlots.clear()

            return MenuResponse.Refresh
        end)

        -- hidden slots
        local hiddenSlotsButton = rootDescription:CreateButton(L('HIDDEN_SLOTS'))

        hiddenSlotsButton:SetTooltip(getOptionTooltipFn(L('HIDDEN_SLOTS'), L('HIDDEN_SLOTS_TOOLTIP')))

        for _, invSlotId in ipairs(setSlotOptions) do
            hiddenSlotsButton:CreateCheckbox(
                addon.const.slotLabelMap[invSlotId],
                function () return config.hiddenSlots.has(invSlotId) end,
                function () config.hiddenSlots.set(invSlotId, not config.hiddenSlots.has(invSlotId)) end
            )
        end

        hiddenSlotsButton:CreateButton(L('RESET'), function ()
            config.hiddenSlots.clear()

            return MenuResponse.Refresh
        end)

        rootDescription:CreateDivider()

        -- use character profile
        local useCharacterProfileCheckbox = rootDescription:CreateCheckbox(
            L('USE_CHARACTER_PROFILE'),
            function () return config.characterProfileEnabled() end,
            function () config.setCharacterProfileEnabled(not config.characterProfileEnabled()) end
        )

        useCharacterProfileCheckbox:SetTooltip(getOptionTooltipFn(L('USE_CHARACTER_PROFILE'), L('USE_CHARACTER_PROFILE_TOOLTIP')))

        -- reload button
        rootDescription:CreateButton(L('RELOAD_SETS'), function ()
            addon.setLoader.clearSetData()
            addon.ui.setsTab.refreshIfVisible()
        end)
    end)
end
