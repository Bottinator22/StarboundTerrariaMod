require "/scripts/util.lua"
require "/scripts/vec2.lua"

local ownerId
local targetPos
local approachSpeed = 10
local maxSpeed = 30
local decel = 0.5
function init()
    ownerId = projectile.sourceEntity()
    targetPos = vec2.add(mcontroller.position(), config.getParameter("targetOffset", {0, 0}))
  message.setHandler("offset", function(_, _, pos)
      targetPos = vec2.add(targetPos, pos)
    end)

  message.setHandler("launch", function(_, _, dir)
      mcontroller.setVelocity(vec2.withAngle(dir, 90))
      maxSpeed = 90
      approachSpeed = 0
      decel = 1
    end)
end

function update(dt)
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    local toTarget = vec2.withAngle(dir, approachSpeed)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if vec2.mag(mcontroller.velocity()) > maxSpeed then
        local angle = vec2.angle(mcontroller.velocity())
        local new = vec2.withAngle(angle, maxSpeed)
        mcontroller.setVelocity(new)
    end
end
