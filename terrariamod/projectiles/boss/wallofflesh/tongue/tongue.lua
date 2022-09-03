require "/scripts/util.lua"
require "/scripts/vec2.lua"

local ownerId
function init()
    ownerId = config.getParameter("ownerId")
  message.setHandler("move", function(_, _, pos)
      mcontroller.setPosition(pos)
    end)

  message.setHandler("die", function()
      projectile.die()
    end)
end

function update(dt)
    if not world.entityExists(ownerId) then
        projectile.die()
    end
end
