local addonName, MogPartialSets = ...

MogPartialSetsAddon = MogPartialSets

MogPartialSets.frame = CreateFrame('Frame')
MogPartialSets.loaded = false
MogPartialSets.initialized = false
MogPartialSets.configVersion = 4
MogPartialSets.updateTimer = nil
MogPartialSets.eventHandlers = {
    ADDON_LOADED = 'onAddonLoaded',
    TRANSMOGRIFY_UPDATE = 'onTransmogrifyAction',
    TRANSMOGRIFY_OPEN = 'onTransmogrifyAction',
    GET_ITEM_INFO_RECEIVED = 'onItemInfoReceived',
}
MogPartialSets.apiOverrides = {}
MogPartialSets.isValidSetCache = {}

function MogPartialSets:registerEvents()
    for event, _ in pairs(self.eventHandlers) do
        self.frame:RegisterEvent(event)
    end

    self.frame:SetScript('OnEvent', function (frame, event, ...)
        if self[self.eventHandlers[event]](self, ...) then
            frame:UnregisterEvent(event)
        end
    end)
end

function MogPartialSets:onAddonLoaded(loadedAddonName)
    if loadedAddonName == addonName then
        self:initConfiguration()
        self:prepareGlobalApiOverrides()
        self.loaded = true

        return true
    end
end

function MogPartialSets:prepareApiOverride(apiTable, key, name)
    self.apiOverrides[name] = {
        apiTable = apiTable,
        key = key,
        original = apiTable[key],
    }
end

function MogPartialSets:overrideApi(name, newFunc)
    self.apiOverrides[name].apiTable[self.apiOverrides[name].key] = newFunc
end

function MogPartialSets:callOriginalApi(name, ...)
    return self.apiOverrides[name].original(...)
end

function MogPartialSets:onTransmogrifyAction()
    if self.loaded then
        if not self.initialized and WardrobeCollectionFrame then
            self:initOverrides()
            self:initUi()
            self.initialized = true
        end

        return self.initialized
    end
end

function MogPartialSets:onItemInfoReceived(itemId)
    if self.loaded and self.initialized and itemId > 0 then
        self:updateAfter(0.5)
    end
end

function MogPartialSets:initConfiguration()
    if MogPartialSetsAddonConfig == nil then
        self:setDefaultConfiguration()
        return
    end

    local version = MogPartialSetsAddonConfig.version or 1

    if
        version < self.configVersion and not self:migrateConfiguration(version)
        or version > self.configVersion
    then
        -- reset configuration if migration has failed or the addon was downgraded
        MogPartialSets:setDefaultConfiguration()
    end
end

function MogPartialSets:setDefaultConfiguration()
    MogPartialSetsAddonConfig = {
        enabled = true,
        maxMissingPieces = 2,
        onlyFavorite = false,
        favoriteVariants = false,
        showUnusable = false,
        showHidden = false,
    }
end

function MogPartialSets:migrateConfiguration(from)
    return pcall(function ()
        while from < self.configVersion do
            if from == 1 then
                -- v1 => v2
                MogPartialSetsAddonConfig.onlyFavorite = false
                MogPartialSetsAddonConfig.favoriteVariants = false
            elseif from == 2 then
                -- v2 => v3
                MogPartialSetsAddonConfig.showUnusable = false
            elseif from == 3 then
                -- v2 => v4
                MogPartialSetsAddonConfig.showHidden = false
            end

            from = from + 1
        end

        MogPartialSetsAddonConfig.version = self.configVersion
    end)
end

function MogPartialSets:notifyConfigUpdated()
    self:updateTransmogFrame()
    self:updateUi()
end

function MogPartialSets:prepareGlobalApiOverrides()
    self:prepareApiOverride(C_TransmogSets, 'HasUsableSets', 'hasUsableSets')
    self:prepareApiOverride(C_TransmogSets, 'GetUsableSets', 'getUsableSets')
    self:prepareApiOverride(C_TransmogSets, 'GetSetSources', 'getSetSources')
    self:prepareApiOverride(C_TransmogSets, 'GetSetInfo', 'getSetInfo')
    self:prepareApiOverride(C_TransmogCollection, 'GetSourceInfo', 'getSourceInfo')
end

function MogPartialSets:getAvailableSets()
    local sets = {}

    if MogPartialSetsAddonConfig.showHidden then
        -- try to find all valid sets
        for _, set in ipairs(C_TransmogSets.GetAllSets()) do
            if self:isValidSet(set.setID) then
                sets[set.setID] = set
            end
        end
    else
        -- find base sets and their variants
        for _, set in ipairs(C_TransmogSets.GetBaseSets()) do
            sets[set.setID] = set

            for _, setVariant in ipairs(C_TransmogSets.GetVariantSets(set.setID)) do
                sets[setVariant.setID] = setVariant
            end
        end
    end
    
    return sets
end

function MogPartialSets:isValidSet(setId)
    if self.isValidSetCache[setId] == nil then
        for sourceId in pairs(self:callOriginalApi('getSetSources', setId)) do
            local sourceInfo = self:callOriginalApi('getSourceInfo', sourceId)
            local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
            local slotSources = C_TransmogSets.GetSourcesForSlot(setId, slot)
            local index = WardrobeCollectionFrame_GetDefaultSourceIndex(slotSources, sourceId)

            if slotSources[index] == nil then
                self.isValidSetCache[setId] = false
            end
        end

        if self.isValidSetCache[setId] == nil then
            self.isValidSetCache[setId] = true
        end
    end

    return self.isValidSetCache[setId]
end

function MogPartialSets:getSetProgress(setId)
    local collectedSlots
    local usableSlots
    local totalSlots
    local sources = C_TransmogSets.GetSetSources(setId)

    if sources then
        collectedSlots = 0
        usableSlots = 0
        totalSlots = 0

        for sourceId, collected in pairs(sources) do
            totalSlots = totalSlots + 1

            if collected then
                collectedSlots = collectedSlots + 1

                if self:isUsableSource(sourceId) then
                    usableSlots = usableSlots + 1
                end
            end
        end
    end

    return collectedSlots, usableSlots, totalSlots
end

function MogPartialSets:isUsableSource(sourceId)
    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceId)

    if not sourceInfo then
        return false
    end

    local appearanceSources = C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID)

    if not appearanceSources then
        return false
    end

    for _, appearanceInfo in pairs(appearanceSources) do
        -- check isCollected, useError and make sure the item is loaded
        -- (useError may only be available after the item has been loaded)
        if appearanceInfo.isCollected and appearanceInfo.useError == nil and GetItemInfo(appearanceInfo.itemID) ~= nil then
            return true
        end
    end

    return false
end

function MogPartialSets:setHasFavoriteVariant(set, availableSets)
    local baseSetId

    if set.baseSetID then
        -- this is a variant set
        baseSetId = set.baseSetID

        -- check whether the base set is favorited
        if availableSets[set.baseSetID] and availableSets[set.baseSetID].favorite then
            return true
        end
    else
        -- this is a base set
        baseSetId = set.setID
    end

    -- check variants of the base set
    local variants = C_TransmogSets.GetVariantSets(baseSetId)

    if type(variants) == 'table' then
        for _, set in ipairs(variants) do
            if set.favorite then
                return true
            end
        end
    end

    return false
end

function MogPartialSets:isTransmogrifyingSets()
    return WardrobeCollectionFrame:IsVisible() and WardrobeCollectionFrame.selectedTab == 2 and WardrobeFrame_IsAtTransmogrifier()
end

function MogPartialSets:normalizeSearchString(string)
    return string.lower(strtrim(string))
end

function MogPartialSets:stringMatchesSearch(string, normalizedSearch)
    return string.find(self:normalizeSearchString(string), normalizedSearch, 1, true) ~= nil
end

function MogPartialSets:getProgressColor(current, max)
    if current >= max then
        return 'ff008000'
    elseif max > 0 and current / max >= 0.49 then
        return 'fffea000'
    else
        return 'ff800000'
    end
end

function MogPartialSets:initOverrides()
    local gettingPartialUsableSets = true
    local updatingTransmogSets = false

    -- extend C_TransmogSets.HasUsableSets
    self:overrideApi('hasUsableSets', function ()
        return self:callOriginalApi('hasUsableSets') or #C_TransmogSets.GetUsableSets() > 0
    end)

    -- extend C_TransmogSets.GetUsableSets
    self:overrideApi('getUsableSets', function ()
        -- call original function if partial sets are disabled
        if not MogPartialSetsAddonConfig.enabled then
            return self:callOriginalApi('getUsableSets')
        end

        -- find partial sets
        local search
        local hasSearch = false

        if self:isTransmogrifyingSets() then
            search = self:normalizeSearchString(WardrobeCollectionFrameSearchBox:GetText())
            hasSearch = #search > 0
        end

        local usableSets = {}

        MogPartialSets:tryFinally(
            function ()
                gettingPartialUsableSets = true

                local availableSets = self:getAvailableSets();

                for _, set in pairs(availableSets) do
                    local collectedSlots, usableSlots, totalSlots = self:getSetProgress(set.setID)

                    if
                        totalSlots
                        and collectedSlots > 0
                        and (usableSlots > 0 or MogPartialSetsAddonConfig.showUnusable)
                        and (
                            MogPartialSetsAddonConfig.maxMissingPieces <= 0
                            or (totalSlots - collectedSlots) <= MogPartialSetsAddonConfig.maxMissingPieces 
                        )
                        and (
                            not MogPartialSetsAddonConfig.onlyFavorite
                            or (
                                set.favorite
                                or MogPartialSetsAddonConfig.favoriteVariants and MogPartialSets:setHasFavoriteVariant(set, availableSets)
                            )
                        )
                        and (
                            not hasSearch
                            or self:stringMatchesSearch(set.name, search)
                            or set.label ~= nil and self:stringMatchesSearch(set.label, search)
                        )
                    then
                        set.collected = true

                        table.insert(usableSets, set)
                    else
                        set.collected = false
                    end
                end
            end,
            function ()
                gettingPartialUsableSets = false
            end
        )

        return usableSets
    end)

    -- hook SetsTransmogFrame.UpdateSets
    self:prepareApiOverride(WardrobeCollectionFrame.SetsTransmogFrame, 'UpdateSets', 'updateSets')

    self:overrideApi('updateSets', function (frameSelf)
        MogPartialSets:tryFinally(
            function ()
                updatingTransmogSets = true
                self:callOriginalApi('updateSets', frameSelf)
            end,
            function ()
                updatingTransmogSets = false
            end
        )
    end)

    -- extend C_TransmogSets.GetSetSources
    self:overrideApi('getSetSources', function (setId)
        -- if transmog sets are being updated, return only the collected pieces
        -- so that the models reflect the missing pieces
        if updatingTransmogSets and not gettingPartialUsableSets then
            local collectedSources = {}

            for sourceId, collected in pairs(self:callOriginalApi('getSetSources', setId)) do
                if collected then
                    collectedSources[sourceId] = true
                end
            end

            return collectedSources
        end

        -- otherwise behave as normal
        return self:callOriginalApi('getSetSources', setId)
    end)

    -- extend C_TransmogSets.GetSetInfo
    self:overrideApi('getSetInfo', function (setId)
        local set = self:callOriginalApi('getSetInfo', setId)

        if set and self:isTransmogrifyingSets() then
            local collectedSlots, usableSlots, totalSlots = self:getSetProgress(setId)

            if totalSlots then
                local usabilitySuffix = ''

                if usableSlots ~= collectedSlots then
                    usabilitySuffix = string.format(', usable:|r |c%s%d/%d|r', self:getProgressColor(usableSlots, totalSlots), usableSlots, totalSlots)
                end

                set.label = string.format(
                    '%s\n|cff808080(collected:|r |c%s%d/%d|r|cff808080%s|cff808080)|r',
                    set.label or '',
                    self:getProgressColor(collectedSlots, totalSlots),
                    collectedSlots,
                    totalSlots,
                    usabilitySuffix
                 )
            end
        end

        return set
    end)

    -- hook C_TransmogCollection.GetSourceInfo
    self:overrideApi('getSourceInfo', function (sourceId)
        local source = self:callOriginalApi('getSourceInfo', sourceId)

        -- fill in missing quality on few set items so set tooltips don't get stuck on "retrieving item information"
        if source and source.quality == nil and self:isTransmogrifyingSets() then
            source.quality = 4 -- assume epic
        end

        return source
    end)

    -- print info
    print(string.format(
        '|cffffd700<%s>|r |cff808080(v%s by %s)|r |cff4747ffloaded|r',
        addonName,
        GetAddOnMetadata(addonName, 'Version'),
        GetAddOnMetadata(addonName, 'Author')
    ))
end

function MogPartialSets:initUi()
    -- anchor the sets filter UI to the the transmog sets frame
    local setsTmogFrame = WardrobeCollectionFrame.SetsTransmogFrame

    MogPartialSetsFilterButton:SetParent(setsTmogFrame)
    MogPartialSetsFilterButton:SetPoint('LEFT', WardrobeCollectionFrameSearchBox, 'RIGHT', 2, -1)
    MogPartialSetsFilterButton:Show()

    MogPartialSetsFilter:SetParent(UIFrame)

    -- hide sets filter when transmog UI is hidden or tabs are switched
    hooksecurefunc('WardrobeCollectionFrame_SetTab', function ()
        MogPartialSetsFilter:Hide()
    end)

    hooksecurefunc(WardrobeFrame, 'Hide', function ()
        MogPartialSetsFilter:Hide()
    end)

    -- update ui
    self:updateUi()
end

function MogPartialSets:updateUi()
    if MogPartialSetsAddonConfig.enabled then
        MogPartialSetsFilterOnlyFavoriteButton:SetAlpha(1)
        MogPartialSetsFilterOnlyFavoriteButton:Enable()
        MogPartialSetsFilterOnlyFavoriteText:SetAlpha(1)

        MogPartialSetsFilterMaxMissingPiecesEditBox:SetAlpha(1)
        MogPartialSetsFilterMaxMissingPiecesEditBox:Enable()
        MogPartialSetsFilterMaxMissingPiecesText:SetAlpha(1)

        MogPartialSetsFilterShowUnusableButton:SetAlpha(1)
        MogPartialSetsFilterShowUnusableButton:Enable()
        MogPartialSetsFilterShowUnusableText:SetAlpha(1)

        MogPartialSetsFilterShowHiddenButton:SetAlpha(1)
        MogPartialSetsFilterShowHiddenButton:Enable()
        MogPartialSetsFilterShowHiddenText:SetAlpha(1)
    else
        MogPartialSetsFilterOnlyFavoriteButton:SetAlpha(0.5)
        MogPartialSetsFilterOnlyFavoriteButton:Disable()
        MogPartialSetsFilterOnlyFavoriteText:SetAlpha(0.5)

        MogPartialSetsFilterMaxMissingPiecesEditBox:SetAlpha(0.5)
        MogPartialSetsFilterMaxMissingPiecesEditBox:Disable()
        MogPartialSetsFilterMaxMissingPiecesText:SetAlpha(0.5)

        MogPartialSetsFilterShowUnusableButton:SetAlpha(0.5)
        MogPartialSetsFilterShowUnusableButton:Disable()
        MogPartialSetsFilterShowUnusableText:SetAlpha(0.5)

        MogPartialSetsFilterShowHiddenButton:SetAlpha(0.5)
        MogPartialSetsFilterShowHiddenButton:Disable()
        MogPartialSetsFilterShowHiddenText:SetAlpha(0.5)
    end

    if MogPartialSetsAddonConfig.enabled and MogPartialSetsAddonConfig.onlyFavorite then
         MogPartialSetsFilterFavoriteVariantsButton:SetAlpha(1)
         MogPartialSetsFilterFavoriteVariantsButton:Enable()
         MogPartialSetsFilterFavoriteVariantsText:SetAlpha(1)
    else
         MogPartialSetsFilterFavoriteVariantsButton:SetAlpha(0.5)
         MogPartialSetsFilterFavoriteVariantsButton:Disable()
         MogPartialSetsFilterFavoriteVariantsText:SetAlpha(0.5)
    end
end

function MogPartialSets:updateAfter(delay)
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    self.updateTimer = C_Timer.NewTimer(delay, function ()
        self:updateTransmogFrame()
        self.updateTimer = nil
    end)
end

function MogPartialSets:updateTransmogFrame()
    WardrobeCollectionFrame.SetsTransmogFrame:OnEvent('TRANSMOG_COLLECTION_UPDATED')
end

function MogPartialSets:tryFinally(try, finally, ...)
    local status, err = pcall(try, ...)

    finally()

    if not status then
        error(err)
    end
end

-- register events
MogPartialSets:registerEvents()
