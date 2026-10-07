-- Battery for lualine: one async command per minute, the component only reads
-- the cache. No battery (e.g. RHEL6 desktop) -> get()/get_icon() return "".
local M = {}

M.pct, M.charging = nil, false

local cmd = ({
    macos = { "pmset", "-g", "batt" },
    linux = { "sh", "-c", "cat /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/BAT*/status 2>/dev/null" },
    windows = { "powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_Battery).EstimatedChargeRemaining; (Get-CimInstance Win32_Battery).BatteryStatus" },
})[vim.g.os]

local function update()
    if not cmd then return end
    vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
        local out = res.stdout or ""
        local st
        if vim.g.os == "macos" then
            M.pct = tonumber(out:match("(%d+)%%"))
            st = (out:match("%d+%%; ([^;]+);") or ""):lower()
            M.charging = st:find("^charging") ~= nil or st:find("finishing") ~= nil
        elseif vim.g.os == "linux" then
            local pct, s = out:match("(%d+)%s+([%a ]+)")
            M.pct = tonumber(pct)
            st = (s or ""):lower()
            M.charging = st == "charging"
        else
            local pct, s = out:match("(%d+)%s+(%d+)")
            M.pct = tonumber(pct)
            st = s == "2" and "ac" or "discharging"
            M.charging = st == "ac" and M.pct ~= nil and M.pct < 100
        end
        -- No battery (e.g. a desktop): no point polling further.
        if M.pct == nil then
            M._timer:stop()
        end
    end))
end

local pct_icon = {
    [100] = "󰁹",
    [90]  = "󰂂",
    [80]  = "󰂁",
    [70]  = "󰂀",
    [60]  = "󰁿",
    [50]  = "󰁾",
    [40]  = "󰁽",
    [30]  = "󰁼",
    [20]  = "󰁻",
    [10]  = "󰁺",
}

function M.get()
    if M.pct ~= nil then
        return tostring(M.pct)
    end
    return ""
end

function M.get_icon()
    if M.charging then
        return "󰂄"
    elseif M.pct ~= nil then
        local pct = math.floor((M.pct + 9) / 10) * 10
        return pct_icon[pct]
    else
        return ""
    end
end

M._timer = vim.uv.new_timer()
M._timer:start(1000, 60000, vim.schedule_wrap(update))

return M
