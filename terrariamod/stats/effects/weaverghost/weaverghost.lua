function init()
end

function update(dt)
    alpha = status.statusProperty("alpha", 0)
    alpha = math.max(math.min(alpha, 255), 0)
    effect.setParentDirectives(string.format("?multiply=ffffff%02x", math.floor(alpha)))
end

function uninit()
end
