require "/scripts/vec2.lua"

function activate(fireMode, shiftHeld)
  if not storage.firing then
    self.active = true
    local offset = {0, 5}
    world.spawnMonster("skeletron", vec2.add(mcontroller.position(), offset), { level = 2})
    item.consume(1)
  end
end


function firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self.fireOffset))
end

function aimVector()
  local aimVector = vec2.rotate({1, 0}, self.aimAngle + sb.nrand(config.getParameter("inaccuracy", 0), 0))
  aimVector[1] = aimVector[1] * self.aimDirection
  return aimVector
end

function holdingItem()
  return true
end

function recoil()
  return false
end

function outsideOfHand()
  return false
end
