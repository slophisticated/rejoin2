local Logger = require("core.logger")

local Alarm = {}
local WIB_OFFSET = 7 * 60 * 60

local function leapYear(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function daysInMonth(year, month)
    local days = { 31, leapYear(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return days[month]
end

-- Days since 1970-01-01, independent of the Android device's local timezone.
local function daysFromCivil(year, month, day)
    local y = year
    if month <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local adjustedMonth = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * adjustedMonth + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function validTime(value)
    if type(value) ~= "string" then return nil end
    local hour, minute = value:match("^(%d%d):(%d%d)$")
    hour, minute = tonumber(hour), tonumber(minute)
    if not hour or not minute or hour > 23 or minute > 59 then return nil end
    return string.format("%02d:%02d", hour, minute), hour * 60 + minute
end

local function parseDate(value)
    if type(value) ~= "string" then return nil end
    local day, month, year = value:match("^(%d%d)/(%d%d)/(%d%d%d%d)$")
    if not day then day, month = value:match("^(%d%d)/(%d%d)$") end
    day, month, year = tonumber(day), tonumber(month), tonumber(year)
    if not day or not month or month < 1 or month > 12 then return nil end
    return day, month, year
end

local function epochAtWib(year, month, day, time)
    local _, minuteOfDay = validTime(time)
    if not minuteOfDay then return nil end
    return daysFromCivil(year, month, day) * 86400 + minuteOfDay * 60 - WIB_OFFSET
end

local function resolveDate(date, time, now)
    local day, month, year = parseDate(date)
    if not day then return nil, "tanggal harus format DD/MM atau DD/MM/YYYY" end
    now = now or os.time()
    local current = os.date("!*t", now + WIB_OFFSET)
    local lastYear = year or (current.year + 8)
    local firstYear = year or current.year
    for candidateYear = firstYear, lastYear do
        if candidateYear >= 1970 and candidateYear <= 9999
            and day <= daysInMonth(candidateYear, month) then
            local due = epochAtWib(candidateYear, month, day, time)
            if due and due > now then
                return string.format("%02d/%02d/%04d", day, month, candidateYear), due
            end
        end
    end
    if year then return nil, "tanggal dan jam harus di masa depan dan merupakan tanggal kalender yang valid" end
    return nil, "tidak menemukan tanggal berikutnya yang valid"
end

local function nextDailyAt(time, now)
    now = now or os.time()
    local today = os.date("!*t", now + WIB_OFFSET)
    local due = epochAtWib(today.year, today.month, today.day, time)
    if due <= now then due = due + 86400 end
    return due
end

local function findInstance(id)
    for _, inst in ipairs(require("managers.instance").getAll()) do
        if tonumber(inst.id) == tonumber(id) then return inst end
    end
end

function Alarm.set(id, date, time, daily)
    local inst = findInstance(id)
    if not inst then return false, "clone tidak ditemukan" end
    local normalizedTime = validTime(time)
    if not normalizedTime then return false, "waktu harus format HH:MM WIB (00:00–23:59)" end
    local scheduledDate, scheduledAt = resolveDate(date, normalizedTime)
    if not scheduledDate then return false, scheduledAt end
    local previous = inst.logoutAlarm
    inst.logoutAlarm = {
        date = scheduledDate,
        time = normalizedTime,
        daily = daily == true,
        nextAt = scheduledAt,
        timezone = "Asia/Jakarta",
    }
    local ok, err = require("managers.instance").save()
    if not ok then inst.logoutAlarm = previous; return false, "gagal menyimpan alarm: " .. tostring(err) end
    return true, string.format("alarm logout %s %s WIB untuk %s%s", scheduledDate, normalizedTime,
        inst.name or inst.package or tostring(inst.id), daily and " (berulang setiap hari)" or " (sekali)")
end

function Alarm.remove(id)
    local inst = findInstance(id)
    if not inst then return false, "clone tidak ditemukan" end
    if type(inst.logoutAlarm) ~= "table" then return false, "clone ini belum punya alarm logout" end
    local previous = inst.logoutAlarm
    inst.logoutAlarm = nil
    local ok, err = require("managers.instance").save()
    if not ok then inst.logoutAlarm = previous; return false, "gagal menghapus alarm: " .. tostring(err) end
    return true, "alarm logout dihapus untuk " .. tostring(inst.name or inst.package or inst.id)
end

function Alarm.tick(instances, launchBusy)
    local now = os.time()
    for _, inst in ipairs(instances or {}) do
        local alarm = inst.logoutAlarm
        local dueAt = type(alarm) == "table" and tonumber(alarm.nextAt) or nil
        if dueAt and now >= math.max(dueAt, tonumber(alarm.retryAt) or 0) then
            if launchBusy then return end
            local wib = os.date("!*t", now + WIB_OFFSET)
            local today = string.format("%04d-%02d-%02d", wib.year, wib.month, wib.day)
            if alarm.daily and alarm.lastRunDate == today then
                alarm.nextAt = nextDailyAt(alarm.time, now + 1)
            else
                local okCall, ok, message = pcall(require("managers.cookie_injector").logout, inst)
                local completed = okCall and (ok or tostring(message):find("memang sudah logout", 1, true))
                if completed then
                    Logger.info("Logout alarm: " .. tostring(inst.name or inst.package) .. " -> " .. tostring(message))
                    if alarm.daily then
                        alarm.lastRunDate = today
                        alarm.nextAt = nextDailyAt(alarm.time, now + 1)
                        alarm.retryAt = nil
                    else
                        inst.logoutAlarm = nil
                    end
                else
                    alarm.retryAt = now + 60
                    Logger.warn("Logout alarm gagal untuk " .. tostring(inst.name or inst.package)
                        .. "; dicoba lagi sekitar 60 detik: " .. tostring(okCall and message or ok))
                end
            end
            local saved, err = require("managers.instance").save()
            if not saved then Logger.error("Logout alarm: gagal menyimpan status alarm: " .. tostring(err)) end
        end
    end
end

Alarm.validTime = validTime
Alarm.parseDate = parseDate
Alarm.resolveDate = resolveDate
Alarm.nextDailyAt = nextDailyAt
return Alarm
