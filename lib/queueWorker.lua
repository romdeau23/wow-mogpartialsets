---@class Addon
local addon = select(2, ...)

---@class QueueWorkerLib.Task
---@field key any
---@field args Packed<any>
---@field next QueueWorkerLib.Task?

---@param executor function should do the work, receives any extra args passed to add()
---@param updater fun() should do any related updates, called after a batch of tasks is done
---@param frameTimeLimit number max work duration per 1 frame (must be > 0)
---@param updaterFreq number max frequency of calling the updater (must be >= 0)
---@return QueueWorkerLib.Worker
function addon.createQueueWorker(executor, updater, frameTimeLimit, updaterFreq)
    assert(frameTimeLimit > 0)
    assert(updaterFreq >= 0)

    ---@class QueueWorkerLib.Worker
    local worker = {}
    ---@type QueueWorkerLib.Task?
    local nextTask
    ---@type QueueWorkerLib.Task?
    local lastTask
    ---@type table<any, true>
    local pendingKeyMap = {}
    ---@type number
    local spentTime = 0
    ---@type number|nil
    local lastUpdaterCall
    ---@type boolean
    local updaterScheduled = false
    ---@type boolean
    local scheduled = false

    local execute, schedule, scheduleUpdater, runUpdater, processQueue

    ---@return Packed<any> result
    function execute(...)
        local startTime = GetTimePreciseSec()
        local result = addon.pack(pcall(executor, ...))
        spentTime = spentTime + (GetTimePreciseSec() - startTime)

        return result
    end

    function schedule()
        C_Timer.After(0, processQueue)
        scheduled = true
    end

    function runUpdater()
        lastUpdaterCall = GetTimePreciseSec()
        updaterScheduled = false
        updater()
    end

    function scheduleUpdater()
        if updaterScheduled then
            return
        end

        local delay

        if not lastUpdaterCall then
            delay = updaterFreq
        else
            delay = math.max(0, updaterFreq - (GetTimePreciseSec() - lastUpdaterCall))
        end

        C_Timer.After(delay, runUpdater)
        updaterScheduled = true
    end

    function processQueue()
        spentTime = 0
        scheduled = false

        if not nextTask then
            return
        end

        while nextTask and spentTime < frameTimeLimit do
            local result = execute(unpack(nextTask.args, 1, nextTask.args.n))

            pendingKeyMap[nextTask.key] = nil
            nextTask = nextTask.next

            if not nextTask then
                lastTask = nil
            end

            if not result[1] then
                CallErrorHandler(result[2])
            end
        end

        scheduleUpdater()

        if nextTask and not scheduled then
            schedule()
        end
    end

    ---@return any ... executor's return value if it ran immediately, otherwise nothing
    function worker.add(key, ...)
        -- skip if already queued
        if pendingKeyMap[key] then
            return
        end

        -- always mark as pending (re-entrancy)
        pendingKeyMap[key] = true

        -- execute right away if possible
        if spentTime < frameTimeLimit then
            local result = execute(...)

            pendingKeyMap[key] = nil
            scheduleUpdater()

            if not result[1] then
                CallErrorHandler(result[2])
            end

            return unpack(result, 2, result.n)
        end

        -- otherwise queue
        local task = {key = key, args = addon.pack(...)}

        if lastTask then
            lastTask.next = task
            lastTask = task
        else
            nextTask = task
            lastTask = task
        end

        if not scheduled then
            schedule()
        end
    end

    ---@return boolean
    function worker.busy()
        return nextTask ~= nil
    end

    ---@param limit number
    function worker.setFrameTimeLimit(limit)
        assert(limit > 0)
        frameTimeLimit = limit
    end

    ---@param freq number
    function worker.setUpdaterFreq(freq)
        assert(freq >= 0)
        updaterFreq = freq
    end

    return worker
end
