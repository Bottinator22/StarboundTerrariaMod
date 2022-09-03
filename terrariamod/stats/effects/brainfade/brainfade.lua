local life = 0
local fadein
function init()
    fadein = config.getParameter("fadeIn", false)
end

function update(dt)
    if not fadein then
        for i,v in next, status.activeUniqueStatusEffectSummary() do
            if v[1] == "brainfadein" then
                effect.expire()
                break
            end
        end
    end
  life = life + 10
    local alpha = 255 - life
    if fadein then
        alpha = life
    end
    alpha = math.max(math.min(alpha, 255), 0)
    world.debugText(life, mcontroller.position(), "red")
    effect.setParentDirectives(string.format("?multiply=ffffff%02x", math.floor(alpha)))
end

function uninit()
end
