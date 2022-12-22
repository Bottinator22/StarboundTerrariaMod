require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/actions/terra_spawnLeveled.lua"

local fireTime = 0
local fireballFireTime = 0
local ownerId
local initialized
local targetId
local queryRange
local keepTargetInRange
local targets
local outOfSight
local targetCheckTPS
local targetCheckTime
local secondPhase = false
local maxSpeed = 35
local approachSpeed = 0.75
local mouthOpenTime = 0
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = false
ownerId = config.getParameter("ownerId")
initialized = false
  targetId = nil
  queryRange = 100
  keepTargetInRange = 250
  targets = {}
targetCheckTPS = 10
targetCheckTime = 1
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
  
  monster.setDamageBar("Special")
  
  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", {})
  
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
            local newTargets = world.entityQuery(mcontroller.position(), queryRange, {includedTypes = {"player","npc","monster"}})
            table.sort(newTargets, function(a, b)
                return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
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
            if not world.entityExists(testTargetId) or world.magnitude(world.entityPosition(testTargetId), mcontroller.position()) > keepTargetInRange then
                table.remove(targets, 1)
                testTargetId = nil
            end
            if not testTargetId or not entity.isValidTarget(testTargetId) then
                table.remove(targets, 1)
                testTargetId = nil
            end
            targetId = testTargetId
        until #targets <= 0 or targetId
        targetCheckTime = 0
    end
end
function firing()
    if not targetId then
        return
    end
    if not world.entityExists(targetId) then
        return
    end
    --local targetPosition = world.entityPosition(targetId)
    --if targetPosition then
    --    world.debugLine(mcontroller.position(), targetPosition, "red") -- boss -> target red line
    --end
    fireTime = fireTime - 1
    if fireTime <= 0 then
        if status.resourcePercentage("health") < 0.5 then
            if not status.resourcePositive("stunned") then
                animator.playSound("fire")
                local shootPos = vec2.add(mcontroller.position(), animator.partPoint("eyes", "laserPos"))
                local dir = vec2.angle(world.distance(world.entityPosition(targetId), shootPos))
                local approach = {math.cos(dir), math.sin(dir)}
                local toTarget = vec2.mul(approach,1)
                spawnLeveled.spawnProjectile("golemlaser", shootPos, entity.id(), toTarget, false, {level=monster.level(),power=10})
                if secondPhase then
                    shootPos = vec2.add(mcontroller.position(), animator.partPoint("eyes", "laserPos2"))
                    local dir = vec2.angle(world.distance(world.entityPosition(targetId), shootPos))
                    local approach = {math.cos(dir), math.sin(dir)}
                    local toTarget = vec2.mul(approach,1)
                    spawnLeveled.spawnProjectile("golemlaser", shootPos, entity.id(), toTarget, false, {level=monster.level(),power=15})
                end
            end
        end
        fireTime = 25 + 100 * (status.resourcePercentage("health") + (world.entityHealth(ownerId)[1] / world.entityHealth(ownerId)[2]))
    end
    fireballFireTime = fireballFireTime - 1
    if fireballFireTime <= 0 then
        if not status.resourcePositive("stunned") then
            animator.playSound("fireball")
            local shootPos = vec2.add(mcontroller.position(), animator.partPoint("head", "mouthPos"))
            local dir = vec2.angle(world.distance(world.entityPosition(targetId), shootPos))
            local approach = {math.cos(dir), math.sin(dir)}
            local toTarget = vec2.mul(approach,1)
            local power = 6 + 4 * (2 - (status.resourcePercentage("health") + (world.entityHealth(ownerId)[1] / world.entityHealth(ownerId)[2])))
            spawnLeveled.spawnProjectile("golemfireball", shootPos, entity.id(), toTarget, false, {level=monster.level(),power=power})
            mouthOpenTime = 20
        end
        fireballFireTime = 25 + 50 * (status.resourcePercentage("health") + (world.entityHealth(ownerId)[1] / world.entityHealth(ownerId)[2]))
    end
    if mouthOpenTime > 0 then
        mouthOpenTime = mouthOpenTime - 1
        animator.setGlobalTag("mouth", "open")
    else
        animator.setGlobalTag("mouth", "closed")
    end
end
function update(dt)
  if not world.entityExists(ownerId) then
    self.shouldDie = true
    return
  else
      monster.setDamageTeam(world.entityDamageTeam(ownerId))
  end
  if status.resource("health") <= 0 then
      monster.setDamageBar("None")
      animator.setAnimationState("thruster", "active")
      animator.setAnimationState("head", "free")
      secondPhase = true
      status.setPersistentEffects("invuln", {{stat="invulnerable",amount=1}})
      world.callScriptedEntity(ownerId, "doSecondPhase")
      monster.setAggressive(false)
  end
  monster.setDamageOnTouch(true)
  targeting()
  firing()
  if not secondPhase then
      mcontroller.setVelocity({0, 0})
      mcontroller.setPosition(vec2.add(world.entityPosition(ownerId), {0.125, 4.125}))
  end
  if targetId then
      if not secondPhase then
        -- turn head
        local diff = world.distance(mcontroller.position(), world.entityPosition(targetId))
        local xd = diff[1]
        if status.resourcePercentage("health") < 0.5 then
            if math.abs(xd) > 5 then
                if xd > 0 then
                    animator.setAnimationState("head", "left")
                else
                    animator.setAnimationState("head", "right")
                end
            else
                animator.setAnimationState("head", "idle")
            end
        end
      else 
          local targetPos = vec2.add(world.entityPosition(targetId), {0, 15})
          move(targetPos)
      end
  else
      if secondPhase then
          move(vec2.add(world.entityPosition(ownerId), {0, 10}))
      end
  end
end

function move(targetPos)
    local decel = 0.999
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    local approach = {math.cos(dir), math.sin(dir)}
    local toTarget = vec2.mul(approach,approachSpeed)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > maxSpeed then
        local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
        local approach = {math.cos(angle), math.sin(angle)}
        local new = vec2.mul(approach, maxSpeed)
        mcontroller.setVelocity(new)
    end
end
function interact(args)
end

function shouldDie()
    return self.shouldDie
end

function die()
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
