
local moonlord
local noMoonLordTimer = 0
local dead = false
function init()
   dead = status.statusProperty("moonlorddead", false)
   effect.setParentDirectives("saturation=-10?multiply=CFEFDFFF")
end

function update(dt)
    if not status.resourcePositive("health") then
        effect.expire()
    end
    status.setStatusProperty("moonlorddead", dead)
    if dead then
        if dead and not moonlord then
            effect.expire()
            status.setStatusProperty("moonlorddead", false)
        elseif dead and not world.entityExists(moonlord) then
            effect.expire()
            status.setStatusProperty("moonlorddead", false)
        end
        return -- don't respawn the boss
    end
    if moonlord then
        if world.entityExists(moonlord) then
            if world.entityHealth(moonlord)[1] <= 0 then
                dead = true
            end
        else
            moonlord = nil
        end
    else
        local monsters = world.monsterQuery(mcontroller.position(), 400, {order="nearest"})
        for k,v in next,monsters do
            if world.entityTypeName(v) == "moonlord" then
                moonlord = v
                break
            end
        end
        if world.entityType(effect.sourceEntity()) ~= "player" then
            return
        end
        noMoonLordTimer = noMoonLordTimer + 1
        if noMoonLordTimer > 8 then
            noMoonLordTimer = 0
            --world.spawnMonster("moonlord", mcontroller.position(), {level=10})
        end
    end
end

function uninit()
end
