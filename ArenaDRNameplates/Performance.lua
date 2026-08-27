local _, ns = ...
ns = ns or {}

local Performance = {}
ns.Performance = Performance

Performance.active = false
Performance.metrics = {}
Performance.counters = {}

local function NowMilliseconds()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end

    if type(GetTime) == "function" then
        return GetTime() * 1000
    end

    return 0
end

local function CopyStats(source)
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = {
                calls = value.calls or 0,
                total = value.total or 0,
                maximum = value.maximum or 0,
            }
        else
            copy[key] = value
        end
    end
    return copy
end

function Performance:IsActive()
    return self.active == true
end

function Performance:Begin()
    if not self.active then
        return nil
    end

    return NowMilliseconds()
end

function Performance:Finish(metric, startedAt)
    if not self.active or type(metric) ~= "string" or type(startedAt) ~= "number" then
        return
    end

    local elapsed = math.max(NowMilliseconds() - startedAt, 0)
    local stats = self.metrics[metric]
    if not stats then
        stats = { calls = 0, total = 0, maximum = 0 }
        self.metrics[metric] = stats
    end

    stats.calls = stats.calls + 1
    stats.total = stats.total + elapsed
    if elapsed > stats.maximum then
        stats.maximum = elapsed
    end
end

function Performance:Count(counter, amount)
    if not self.active or type(counter) ~= "string" then
        return
    end

    self.counters[counter] = (self.counters[counter] or 0) + (tonumber(amount) or 1)
end

function Performance:GetRemaining()
    if not self.active then
        return 0
    end

    local elapsed = math.max(NowMilliseconds() - (self.startedAt or 0), 0) / 1000
    return math.max((self.duration or 0) - elapsed, 0)
end

function Performance:GetSnapshot()
    return {
        duration = self.duration or 0,
        elapsed = self.active
            and math.max(NowMilliseconds() - (self.startedAt or 0), 0) / 1000
            or self.elapsed or 0,
        metrics = CopyStats(self.metrics),
        counters = CopyStats(self.counters),
    }
end

function Performance:Stop()
    if not self.active then
        return nil
    end

    self.elapsed = math.max(NowMilliseconds() - (self.startedAt or 0), 0) / 1000
    self.active = false

    local timer = self.timer
    self.timer = nil
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end

    local callback = self.onComplete
    self.onComplete = nil
    local snapshot = self:GetSnapshot()
    if type(callback) == "function" then
        callback(snapshot)
    end
    return snapshot
end

function Performance:Start(duration, onComplete)
    if self.active then
        return false, self:GetRemaining()
    end

    self.metrics = {}
    self.counters = {}
    self.duration = math.max(tonumber(duration) or 60, 1)
    self.startedAt = NowMilliseconds()
    self.elapsed = 0
    self.onComplete = onComplete
    self.active = true

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        self.timer = C_Timer.NewTimer(self.duration, function()
            Performance.timer = nil
            Performance:Stop()
        end)
    end

    return true, self.duration
end

