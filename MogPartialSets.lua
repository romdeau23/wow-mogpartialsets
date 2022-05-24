local addonName, MogPartialSets = ...

MogPartialSetsAddon = MogPartialSets

MogPartialSets.frame = CreateFrame('Frame')
MogPartialSets.loaded = false
MogPartialSets.initialized = false
MogPartialSets.configVersion = 7
MogPartialSets.updateTimer = nil
MogPartialSets.pendingModelUpdate = false
MogPartialSets.eventHandlers = {
    ADDON_LOADED = 'onAddonLoaded',
    TRANSMOGRIFY_UPDATE = 'onTransmogrifyAction',
    TRANSMOGRIFY_OPEN = 'onTransmogrifyAction',
    GET_ITEM_INFO_RECEIVED = 'onItemInfoReceived',
}
MogPartialSets.apiOverrides = {}
MogPartialSets.validSetCache = {}
MogPartialSets.setAppearanceCache = {}
MogPartialSets.sourceInfoCache = {}
MogPartialSets.usableSourceCache = {}

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

function MogPartialSets:prepareApiOverride(apiTable, method, identifier)
    self.apiOverrides[identifier or method] = {
        apiTable = apiTable,
        method = method,
        original = apiTable[method],
    }
end

function MogPartialSets:overrideApi(identifier, newFunc)
    self.apiOverrides[identifier].apiTable[self.apiOverrides[identifier].method] = newFunc
end

function MogPartialSets:callOriginalApi(identifier, ...)
    return self.apiOverrides[identifier].original(...)
end

function MogPartialSets:onTransmogrifyAction()
    if self.loaded then
        if not self.initialized and WardrobeCollectionFrame then
            self:prepareWardrobeApiOverrides()
            self:initOverrides()
            self:initUi()
            self.initialized = true
        end

        return self.initialized
    end
end

function MogPartialSets:onItemInfoReceived(itemId)
    if self.loaded and self.initialized and itemId > 0 then
        self:delayedRefresh(true)
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
        self:setDefaultConfiguration()
    end
end

function MogPartialSets:setDefaultConfiguration()
    MogPartialSetsAddonConfig = {
        enabled = true,
        maxMissingPieces = 2,
        onlyFavorite = false,
        favoriteVariants = false,
        ignoredSlotMap = {},
        splash = true,
    }
end

function MogPartialSets:migrateConfiguration(from)
    return pcall(function ()
        while from < self.configVersion do
            if from == 1 then
                -- v1 => v2
                MogPartialSetsAddonConfig.onlyFavorite = false
                MogPartialSetsAddonConfig.favoriteVariants = false
            elseif from == 4 then
                -- v4 => v5 (removes v3, v4)
                MogPartialSetsAddonConfig.showHidden = nil
                MogPartialSetsAddonConfig.showUnusable = nil
                MogPartialSetsAddonConfig.ignoreBracers = false
            elseif from == 5 then
                -- v5 => v6
                MogPartialSetsAddonConfig.ignoredSlotMap = {}

                if MogPartialSetsAddonConfig.ignoreBracers then
                    MogPartialSetsAddonConfig.ignoredSlotMap[Enum.InventoryType.IndexWristType] = true
                end

                MogPartialSetsAddonConfig.ignoreBracers = nil
            elseif from == 6 then
                MogPartialSetsAddonConfig.splash = true
            end

            from = from + 1
        end

        MogPartialSetsAddonConfig.version = self.configVersion
    end)
end

function MogPartialSets:notifyConfigUpdated()
    self:refreshSetsFrame()
    self:updateUi()
end

function MogPartialSets:prepareGlobalApiOverrides()
    self:prepareApiOverride(C_TransmogSets, 'HasUsableSets')
    self:prepareApiOverride(C_TransmogSets, 'GetUsableSets')
    self:prepareApiOverride(C_TransmogSets, 'GetSetPrimaryAppearances')
    self:prepareApiOverride(C_TransmogSets, 'GetSetInfo')
    self:prepareApiOverride(C_TransmogSets, 'GetSourcesForSlot')
    self:prepareApiOverride(C_TransmogSets, 'GetSourceIDsForSlot')
    self:prepareApiOverride(C_TransmogCollection, 'GetSourceInfo')
end

function MogPartialSets:prepareWardrobeApiOverrides()
    self:prepareApiOverride(WardrobeCollectionFrame.SetsTransmogFrame, 'UpdateSets', 'UpdateSets')
    self:prepareApiOverride(WardrobeCollectionFrame.SetsTransmogFrame, 'LoadSet', 'LoadSet')
    self:prepareApiOverride(WardrobeCollectionFrame.SetsTransmogFrame, 'Refresh', 'RefreshSets')
end

function MogPartialSets:setIgnoredSlot(invType, isIgnored)
    if isIgnored then
        MogPartialSetsAddonConfig.ignoredSlotMap[invType] = true
    else
        MogPartialSetsAddonConfig.ignoredSlotMap[invType] = nil
    end

    self:notifyConfigUpdated()
end

function MogPartialSets:isIgnoredSlot(invType)
    return MogPartialSetsAddonConfig.ignoredSlotMap[invType] ~= nil
end

function MogPartialSets:getAvailableSets()
    local sets = {}

    for _, set in ipairs(C_TransmogSets.GetAllSets()) do
        if self:isValidSet(set.setID) then
            sets[set.setID] = set
        end
    end

    return sets
end

function MogPartialSets:isValidSet(setId)
    if self.validSetCache[setId] == nil then
        local valid = false

        for _, appearanceInfo in ipairs(self:getCollectedSetAppearances(setId)) do
            local sourceInfo = self:callOriginalApi('GetSourceInfo', appearanceInfo.appearanceID)

            if sourceInfo then
                local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
                local slotSources = C_TransmogSets.GetSourcesForSlot(setId, slot)
                local index = CollectionWardrobeUtil.GetDefaultSourceIndex(slotSources, appearanceInfo.appearanceID)

                if slotSources[index] then
                    valid = true
                end
            end

            if not valid then
                break
            end
        end

        self.validSetCache[setId] = valid
    end

    return self.validSetCache[setId]
end

function MogPartialSets:getSetProgress(setId)
    local collectedSlots
    local totalSlots
    local appearances = self:getSetAppearances(setId)

    if appearances then
        collectedSlots = 0
        totalSlots = 0

        for _, appearanceInfo in ipairs(appearances) do
            local sourceInfo = self:getCachedSourceInfo(appearanceInfo.appearanceID)

            if sourceInfo and not self:isIgnoredSlot(sourceInfo.invType - 1) then
                totalSlots = totalSlots + 1

                if appearanceInfo.collected or self:getUsableSource(appearanceInfo.appearanceID) ~= nil then
                    collectedSlots = collectedSlots + 1
                end
            end
        end
    end

    return collectedSlots, totalSlots
end

function MogPartialSets:getSetAppearances(setId)
    if self.setAppearanceCache[setId] == nil then
        self.setAppearanceCache[setId] = self:callOriginalApi('GetSetPrimaryAppearances', setId)
    end

    return self.setAppearanceCache[setId]
end

function MogPartialSets:getCollectedSetAppearances(setId)
    local appearances = {}

    for _, appearanceInfo in ipairs(self:getSetAppearances(setId)) do
        if appearanceInfo.collected then
            table.insert(appearances, appearanceInfo)
        else
            local usableAppearance = self:getUsableSource(appearanceInfo.appearanceID)

            if usableAppearance ~= nil then
                table.insert(appearances, {collected = true, appearanceID = usableAppearance.sourceID})
            end
        end
    end

    return appearances
end

function MogPartialSets:getCachedSourceInfo(sourceId)
    if self.sourceInfoCache[sourceId] == nil then
        self.sourceInfoCache[sourceId] = self:callOriginalApi('GetSourceInfo', sourceId)
    end

    return self.sourceInfoCache[sourceId]
end

function MogPartialSets:getUsableSource(appearanceId)
    if self.usableSourceCache[appearanceId] == nil then
        local usableSource
        local loaded = false
        local baseSourceInfo = self:getCachedSourceInfo(appearanceId)

        if baseSourceInfo then
            local appearanceSources = C_TransmogCollection.GetAppearanceSources(baseSourceInfo.visualID)

            if appearanceSources then
                for _, sourceInfo in pairs(appearanceSources) do
                    -- check isCollected, useError and make sure the item is loaded
                    -- (useError may only be available after the item has been loaded)
                    if sourceInfo.isCollected and sourceInfo.useError == nil then
                        usableSource = sourceInfo
                        loaded = GetItemInfo(sourceInfo.itemID) ~= nil
                        break
                    end
                end
            end
        end

        if not loaded then
            -- don't cache items that aren't fully loaded
            return usableSource
        end

        self.usableSourceCache[appearanceId] = {source = usableSource}
    end

    return self.usableSourceCache[appearanceId].source
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
        for _, variant in ipairs(variants) do
            if variant.favorite then
                return true
            end
        end
    end

    return false
end

function MogPartialSets:isTransmogrifyingSets()
    return WardrobeCollectionFrame:IsVisible() and WardrobeCollectionFrame.selectedTab == 2 and C_Transmog.IsAtTransmogNPC()
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
    local gettingUsableSets = false
    local updatingTransmogSets = false
    local loadingSet = false

    self:overrideApi('HasUsableSets', function ()
        return self:callOriginalApi('HasUsableSets') or #C_TransmogSets.GetUsableSets() > 0
    end)

    self:overrideApi('GetUsableSets', function ()
        -- call original function if partial sets are disabled
        if not MogPartialSetsAddonConfig.enabled then
            return self:callOriginalApi('GetUsableSets')
        end

        -- find partial sets
        local search
        local hasSearch = false

        if self:isTransmogrifyingSets() then
            search = self:normalizeSearchString(WardrobeCollectionFrameSearchBox:GetText())
            hasSearch = #search > 0
        end

        local usableSets = {}
        gettingUsableSets = true

        self:tryFinally(
            function ()
                local availableSets = self:getAvailableSets()

                for _, set in pairs(availableSets) do
                    local collectedSlots, totalSlots = self:getSetProgress(set.setID)

                    if
                        totalSlots
                        and collectedSlots > 0
                        and (totalSlots - collectedSlots) <= MogPartialSetsAddonConfig.maxMissingPieces
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
                gettingUsableSets = false
            end
        )

        return usableSets
    end)

    self:overrideApi('UpdateSets', function (frameSelf)
        self:tryFinally(
            function ()
                updatingTransmogSets = true
                self:callOriginalApi('UpdateSets', frameSelf)
            end,
            function ()
                updatingTransmogSets = false
            end
        )
    end)

    self:overrideApi('LoadSet', function (frameSelf, setId)
        self:tryFinally(
            function ()
                loadingSet = true
                self:callOriginalApi('LoadSet', frameSelf, setId)
            end,
            function ()
                loadingSet = false
            end
        )
    end)

    self:overrideApi('RefreshSets', function (frameSelf)
        self:callOriginalApi('RefreshSets', frameSelf, false) -- don't reset
    end)

    self:overrideApi('GetSetPrimaryAppearances', function (setId)
        -- return only collected apperances when loading a set or updating the list
        if not gettingUsableSets and (updatingTransmogSets or loadingSet) then
            return self:getCollectedSetAppearances(setId)
        end

        -- return original sources
        return self:getSetAppearances(setId)
    end)

    self:overrideApi('GetSetInfo', function (setId)
        local set = self:callOriginalApi('GetSetInfo', setId)

        if set and self:isTransmogrifyingSets() then
            local collectedSlots, totalSlots = self:getSetProgress(setId)

            if totalSlots then
                set.label = string.format(
                    '%s\n|cff808080(collected:|r |c%s%d/%d|cff808080)|r',
                    set.label or '',
                    self:getProgressColor(collectedSlots, totalSlots),
                    collectedSlots,
                    totalSlots
                 )
            end
        end

        return set
    end)

    self:overrideApi('GetSourcesForSlot', function (setId, slot)
        local slotSources = self:callOriginalApi('GetSourcesForSlot', setId, slot)
        local hasCollectedSource = false

        for _, sourceInfo in ipairs(slotSources) do
            if sourceInfo.isCollected and sourceInfo.useError == nil then
                hasCollectedSource = true
                break
            end
        end

        if not self:isTransmogrifyingSets() or hasCollectedSource then
            return slotSources
        end

        -- try to add alternative sources from the set
        for _, appearance in pairs(self:getCollectedSetAppearances(setId)) do
            local sourceInfo =  self:callOriginalApi('GetSourceInfo', appearance.appearanceID)

            if sourceInfo and C_Transmog.GetSlotForInventoryType(sourceInfo.invType) == slot then
                table.insert(slotSources, sourceInfo)
                break
            end
        end

        return slotSources
    end)

    self:overrideApi('GetSourceIDsForSlot', function (setId, slot)
        local sourceIds = {}

        for _, sourceInfo in ipairs(C_TransmogSets.GetSourcesForSlot(setId, slot)) do
            table.insert(sourceIds, sourceInfo.sourceID)
        end

        return sourceIds
    end)

    self:overrideApi('GetSourceInfo', function (sourceId)
        local source = self:callOriginalApi('GetSourceInfo', sourceId)

        -- fill in missing quality on few set items so set tooltips don't get stuck on "retrieving item information"
        if source and source.quality == nil and self:isTransmogrifyingSets() then
            source.quality = 4 -- assume epic
        end

        return source
    end)

    if MogPartialSetsAddonConfig.splash then
        print(string.format(
            '|cffffd700<%s>|r |cff808080(v%s by %s)|r |cff4747ffloaded|r',
            addonName,
            GetAddOnMetadata(addonName, 'Version'),
            GetAddOnMetadata(addonName, 'Author')
        ))
    end
end

function MogPartialSets:initUi()
    -- anchor filter button
    MogPartialSetsFilterButton:SetParent(WardrobeCollectionFrame.SetsTransmogFrame)
    MogPartialSetsFilterButton:SetPoint('LEFT', WardrobeCollectionFrameSearchBox, 'RIGHT', 2, -1)
    MogPartialSetsFilterButton:Show()

    -- set filter parent
    MogPartialSetsFilter:SetParent(UIFrame)

    -- handle transmog UI actions
    hooksecurefunc(WardrobeCollectionFrame, 'SetTab', function ()
        -- hide sets filter when transmog UI is hidden or tabs are switched
        MogPartialSetsFilter:Hide()

        -- force refresh after opening the sets tab
        if self:isTransmogrifyingSets() then
            self:delayedRefresh(true)
        end
    end)

    hooksecurefunc(WardrobeFrame, 'Show', function ()
        -- force refresh after re-opening the transmog UI on sets tab
        if self:isTransmogrifyingSets() then
            self:delayedRefresh(true)
        end
    end)

    hooksecurefunc(WardrobeFrame, 'Hide', function ()
        MogPartialSetsFilter:Hide()
    end)

    -- update ui
    self:updateUi()
end

function MogPartialSets:updateUi()
    local enabled = MogPartialSetsAddonConfig.enabled

    local frames = {
        MogPartialSetsFilterOnlyFavoriteButton,
        MogPartialSetsFilterOnlyFavoriteText,
        MogPartialSetsFilterFavoriteVariantsButton,
        MogPartialSetsFilterFavoriteVariantsText,
        MogPartialSetsFilterMaxMissingPiecesEditBox,
        MogPartialSetsFilterMaxMissingPiecesText,
        MogPartialSetsFilterSplashText,
        MogPartialSetsFilterSplashButton,
        MogPartialSetsFilterIgnoredSlotsText,
        MogPartialSetsFilterIgnoreHeadButton,
        MogPartialSetsFilterIgnoreHeadText,
        MogPartialSetsFilterIgnoreCloakButton,
        MogPartialSetsFilterIgnoreCloakText,
        MogPartialSetsFilterIgnoreBracersButton,
        MogPartialSetsFilterIgnoreBracersText,
        MogPartialSetsFilterIgnoreBootsButton,
        MogPartialSetsFilterIgnoreBootsText,
        MogPartialSetsFilterRefreshButton,
    }

    for _, frame in ipairs(frames) do
        self:toggleFilterFrame(frame, enabled)
    end

    if enabled then
        self:toggleFilterFrame(MogPartialSetsFilterFavoriteVariantsButton, MogPartialSetsAddonConfig.onlyFavorite)
        self:toggleFilterFrame(MogPartialSetsFilterFavoriteVariantsText, MogPartialSetsAddonConfig.onlyFavorite)
    end
end

function MogPartialSets:toggleFilterFrame(frame, enabled)
    if enabled then
        frame:SetAlpha(1)
    else
        frame:SetAlpha(0.5)
    end

    if frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
end

function MogPartialSets:forceRefresh()
    self:clearCaches()
    self:refreshSetsFrame(true)
end

function MogPartialSets:delayedRefresh(updateModels)
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if updateModels then
        self.pendingModelUpdate = true
    end

    self.updateTimer = C_Timer.NewTimer(1, function ()
        self:refreshSetsFrame(self.pendingModelUpdate)
        self.updateTimer = nil
        self.pendingModelUpdate = false
    end)
end

function MogPartialSets:refreshSetsFrame(updateModels)
    WardrobeCollectionFrame.SetsTransmogFrame:OnEvent('TRANSMOG_COLLECTION_UPDATED')

    if updateModels then
        for _, model in pairs(WardrobeCollectionFrame.SetsTransmogFrame.Models) do
            model.setID = -1
        end

        WardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
    end
end

function MogPartialSets:clearCaches()
    self.validSetCache = {}
    self.setAppearanceCache = {}
    self.sourceInfoCache = {}
    self.usableSourceCache = {}
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
