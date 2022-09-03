require "/scripts/util.lua"

local ownerId
function init()
    ownerId = config.getParameter("ownerId")
end

function update(dt)
    world.debugText("how", mcontroller.position(), "yellow")
    if not world.entityExists(ownerId) then
        projectile.die()
    else
        mcontroller.setPosition(world.entityPosition(ownerId))
        mcontroller.setVelocity({0, 0})
    end
end
