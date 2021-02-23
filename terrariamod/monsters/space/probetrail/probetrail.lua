require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/drops.lua"
require "/scripts/status.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/tenant.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"

-- Engine callback - called on initialization of entity
function init()
    storage.spawnTime = world.time()
    self.tRotation = config.getParameter("rotation")
  self.life = 0
  self.sD = false
  message.setHandler("despawn", despawn)

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 5))
  mcontroller.setAutoClearControls(false)
  self.behaviorTickRate = config.getParameter("behaviorUpdateDelta", 2)
  self.behaviorTick = 0

  animator.setGlobalTag("flipX", "")

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  monster.setDeathSound(nil)
  animator.resetTransformationGroup("body")
  animator.rotateTransformationGroup("body", self.tRotation)
  monster.setDamageTeam({type = "ghostly", team = 0})
end

function update(dt)
mcontroller.controlFace(1)
  

  if self.behaviorTick >= self.behaviorTickRate then
    self.behaviorTick = self.behaviorTick - self.behaviorTickRate
    clearAnimation()

    updateAnimation()

  end
  self.behaviorTick = self.behaviorTick + 1
  self.life = self.life + 1
  if self.life > 5.0 then
      despawn()
  end
end


function shouldDie()
  return self.sD
end

function despawn()
  monster.setDropPool(nil)
  monster.setDeathParticleBurst(nil)
  monster.setDeathSound(nil)
  status.setResourcePercentage("health", 0)
  die()
  self.sD = true
end
function die()
end

