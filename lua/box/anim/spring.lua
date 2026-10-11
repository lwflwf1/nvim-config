-- Closed-form damped-spring easing for Snacks.animate, parameterized the way
-- nvim-notify's per-frame spring is (frequency in Hz + damping ratio) instead
-- of a raw k. `settle` is the fraction of the distance the spring has covered
-- when the schedule ends (0..1); the remaining bit is snapped by the caller --
-- nvim-notify does the same with its `complete` predicates (opacity <= 4,
-- width < 3). Returns the easing fn (t, b, c, d) for Snacks.animate plus the
-- duration in ms derived from the frequency (k = angular_freq * duration).
--
-- The trajectory is the zero-initial-velocity step response of the spring, so
-- `damping` < 1 gives the small overshoot nvim-notify uses on its exit
-- (damping = 0.9); `damping` > 1 is overdamped (slower settle, no overshoot).
local M = {}

local cache = {}

-- solve (1 + k) * e^-k = 1 - settle for k (critically damped end value);
-- monotone decreasing in k, bisection is plenty
local function solve_k(settle)
    local hit = cache[settle]
    if hit then
        return hit
    end
    local lo, hi = 0.5, 40
    for _ = 1, 60 do
        local mid = (lo + hi) / 2
        if (1 + mid) * math.exp(-mid) > 1 - settle then
            lo = mid
        else
            hi = mid
        end
    end
    cache[settle] = hi
    return hi
end

---@param opts { frequency: number, damping?: number, settle: number }
---@return { easing: fun(t: number, b: number, c: number, d: number): number, duration: number }
function M.new(opts)
    local frequency = opts.frequency
    local damping = opts.damping or 1
    local settle = opts.settle
    local w = frequency * 2 * math.pi -- angular frequency (rad/s)

    -- for damping ~= 1 solve on the envelope: e^(-damping*k) * A = 1 - settle,
    -- where A bounds the oscillation (approximate, but the remainder is snapped
    -- anyway); for damping == 1 use the exact end value
    local k
    if damping == 1 then
        k = solve_k(settle)
    else
        local a = 1 + damping / math.sqrt(math.abs(1 - damping * damping))
        k = math.log(a / (1 - settle)) / damping
    end
    local duration = k / w * 1000

    local easing = function(t, b, c, d)
        local tau = k * (t / d)
        if damping == 1 then
            return b + c * (1 - (1 + tau) * math.exp(-tau))
        elseif damping < 1 then
            local s = math.sqrt(1 - damping * damping)
            return b
                + c
                    * (1 - math.exp(-damping * tau) * (math.cos(s * tau) + damping / s * math.sin(s * tau)))
        else
            local s = math.sqrt(damping * damping - 1)
            return b
                + c
                    * (1 - math.exp(-damping * tau) * (math.cosh(s * tau) + damping / s * math.sinh(s * tau)))
        end
    end

    return { easing = easing, duration = duration }
end

return M
