require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/companions/capturable.lua"

local initialized
local targetId
local queryRange
local keepTargetInRange
local targets
local outOfSight
local targetCheckTPS
local targetCheckTime
local ownerId
local punchTimer = 0
local punchTarget = nil
local punching = false
local fistType
local anchor
local approachSpeed = 50
local anchorDir = 1
local anchorPos
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = true
    fireTime = math.random(0, 250)
initialized = false
  targetId = nil
  queryRange = 50
  keepTargetInRange = 250
  targets = {}
targetCheckTPS = 10
targetCheckTime = 1
fistType = config.getParameter("fistType", "right")
anchor = config.getParameter("anchorPos", {0, 0})
anchorDir = math.max(math.min(anchor[1], 1), -1)
ownerId = config.getParameter("ownerId")
headId = config.getParameter("headId")
monster.setAggressive(true)

  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
  self.notifications = {}
  storage.spawnTime = world.time()
  if storage.spawnPosition == nil or config.getParameter("wasRelocated", false) then
    local position = mcontroller.position()
    local groundSpawnPosition
    if mcontroller.baseParameters().gravityEnabled then
      groundSpawnPosition = findGroundPosition(position, -20, 3)
    end
    storage.spawnPosition = groundSpawnPosition or position
  end

  self.collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)

  animator.setGlobalTag("flipX", "")

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
    end)

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false
  
  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  mcontroller.controlFace(1)
end
function targeting()
    if targetId then
        if not world.entityExists(targetId) then
            targetId = nil
        end
    end
    targetCheckTime = targetCheckTime + 1  
    if targetCheckTime >= targetCheckTPS - 1 then
        if #targets == 0 then
            local newTargets = world.entityQuery(anchorPos, queryRange, {includedTypes = {"player","npc","monster"}})
            table.sort(newTargets, function(a, b)
                return world.magnitude(world.entityPosition(a), anchorPos) < world.magnitude(world.entityPosition(b), anchorPos)
            end)
            for _,entityId in pairs(newTargets) do
                if entity.isValidTarget(entityId) then
                    table.insert(targets, entityId)
                end
            end
        end
        repeat
            targetId = targets[1]
            local testTargetId = targetId
            if testTargetId == nil then break end
            -- {math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}
            if not world.entityExists(testTargetId) or world.magnitude(world.entityPosition(testTargetId), anchorPos) > keepTargetInRange then
                table.remove(targets, 1)
                testTargetId = nil
            end
            if not testTargetId or not entity.isValidTarget(testTargetId) then
                table.remove(targets, 1)
                testTargetId = nil
            end
            if testTargetId then
                local xDis = world.distance(world.entityPosition(testTargetId), anchorPos)[1]
                if (anchorDir > 0 and xDis < 0) or (anchorDir < 0 and xDis > 0) then
                    table.remove(targets, 1)
                    testTargetId = nil
                end
            end
            targetId = testTargetId
        until #targets <= 0 or targetId
        targetCheckTime = 0
    end
end
function update(dt)
    if not world.entityExists(ownerId) then
        status.setResourcePercentage("health", 0)
        return
    else
      monster.setDamageTeam(world.entityDamageTeam(ownerId))
    end
  monster.setDamageOnTouch(true)
  anchorPos = vec2.add(world.entityPosition(ownerId), anchor)
  targeting()
  world.debugLine(mcontroller.position(), anchorPos, "green")
  animator.resetTransformationGroup("flip")
  if fistType == "left" then
      animator.scaleTransformationGroup("flip", {1, -1})
  end
  animator.resetTransformationGroup("body")
  if targetId then
      punchTimer = punchTimer + 1
      if punchTimer > 50 + 50 * ((world.entityHealth(ownerId)[1] / world.entityHealth(ownerId)[2]) + (world.entityHealth(headId)[1] / world.entityHealth(headId)[2])) then
          punchTimer = 0
          punchTarget = world.entityPosition(targetId)
          punching = true
      end
  end
  if punchTarget then
      animator.rotateTransformationGroup("body", vec2.angle(world.distance(mcontroller.position(), anchorPos)))
      if world.magnitude(mcontroller.position(), punchTarget) < 0.5 then
          if punching then
              punching = false
          else
              punchTarget = nil
          end
      end
      if punchTarget then
        if not punching then
          punchTarget = anchorPos
        end
        local dir = vec2.angle(world.distance(punchTarget, mcontroller.position()))
        mcontroller.setVelocity(vec2.withAngle(dir,approachSpeed))
      end
  else
      mcontroller.setPosition(vec2.add(anchorPos, {0.5 * anchorDir, 0}))
      mcontroller.setVelocity({0, 0})
      if fistType == "left" then
        animator.rotateTransformationGroup("body", math.pi)
      end
  end
  local myPos = vec2.add(mcontroller.position(), vec2.mul(mcontroller.velocity(), dt))
  local mag = world.magnitude(myPos, anchorPos) + 0.5
  local dir = vec2.angle(world.distance(anchorPos, myPos))
  animator.resetTransformationGroup("beam")
  animator.scaleTransformationGroup("beam", mag) 
  animator.rotateTransformationGroup("beam", dir)
end

function interact(args)
end

function shouldDie()
    return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
