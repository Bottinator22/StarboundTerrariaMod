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
self.probeHealth = 0
self.probeHealthInit = false
    self.pathing = {}
    --self.size = 0
  self.probe = true
self.probeId = 0
self.ownerId = 1
self.headId = 0
self.childId = 0
self.ownerHealth = 0
self.lastHealth = status.resourcePercentage("health")
setHealth(config.getParameter("ownerHealth"))
setVariables(config.getParameter("ownerId"), 0, config.getParameter("headId"))

    message.setHandler("healthOwner", function(_,_,health)
        --setHealth(health)
        --sendHealthOwner(health)
  end)
    message.setHandler("healthChild", function(_,_,health)
        updateO(health)
        --sendHealthChild(health)
  end)
        message.setHandler("ownerChange", function(_,_,newOwner)
        self.ownerId = newOwner
  end)
      message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
  self.shouldDie = true
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

  self.behavior = behavior.behavior(config.getParameter("behavior"), sb.jsonMerge(config.getParameter("behaviorConfig", {}), skillBehaviorConfig()), _ENV)
  self.board = self.behavior:blackboard()
  self.board:setPosition("spawn", storage.spawnPosition)

  self.collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)
  self.behaviorTickRate = config.getParameter("behaviorUpdateDelta", 2)
  self.behaviorTick = math.random(1, self.behaviorTickRate)

  animator.setGlobalTag("flipX", "")
  self.board:setNumber("facingDirection", mcontroller.facingDirection())

  capturable.init()

  -- Listen to damage taken
  self.damageTaken = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.healthLost > 0 then
        self.damaged = true
        self.board:setEntity("damageSource", notification.sourceEntityId)
              sendHealthOwner(status.resourcePercentage("health"))
                sendHealthChild(status.resourcePercentage("health"))
        if status.resourcePercentage("health") * status.resourceMax("health") < self.probeHealth then
          if self.probe then
            if status.resourcePercentage("health") > 0.01 then
            --releaseProbe()
            end
          end
      end
      end
    end
  end)

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
    end)

  local deathBehavior = config.getParameter("deathBehavior")
  if deathBehavior then
    self.deathBehavior = behavior.behavior(deathBehavior, config.getParameter("behaviorConfig", {}), _ENV, self.behavior:blackboard())
  end

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false

  if config.getParameter("damageBar") then
    monster.setDamageBar(config.getParameter("damageBar"));
  end

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
end

function update(dt)
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  
  capturable.update(dt)
  self.damageTaken:update()

  if status.resourcePositive("stunned") then
    animator.setAnimationState("damage", "stunned")
    animator.setGlobalTag("hurt", "hurt")
    self.stunned = true
    mcontroller.clearControls()
    if self.damaged then
      self.suppressDamageTimer = config.getParameter("stunDamageSuppression", 0.5)
      monster.setDamageOnTouch(false)
    end
    return
  else
    animator.setGlobalTag("hurt", "")
    animator.setAnimationState("damage", "none")
  end

  -- Suppressing touch damage
  if self.suppressDamageTimer then
    monster.setDamageOnTouch(false)
    self.suppressDamageTimer = math.max(self.suppressDamageTimer - dt, 0)
    if self.suppressDamageTimer == 0 then
      self.suppressDamageTimer = nil
    end
  elseif status.statPositive("invulnerable") then
    monster.setDamageOnTouch(false)
  else
    monster.setDamageOnTouch(self.touchDamageEnabled)
  end

  if self.behaviorTick >= self.behaviorTickRate then
    self.behaviorTick = self.behaviorTick - self.behaviorTickRate
    mcontroller.clearControls()

    self.tradingEnabled = false
    self.setFacingDirection = false
    self.moving = false
    self.rotated = false
    self.forceRegions:clear()
    self.damageSources:clear()
    self.damageParts = {}
    clearAnimation()

    if self.behavior then
      local board = self.behavior:blackboard()
      board:setEntity("self", entity.id())
      board:setPosition("self", mcontroller.position())
      board:setNumber("dt", dt * self.behaviorTickRate)
      board:setNumber("facingDirection", self.facingDirection or mcontroller.facingDirection())

      self.behavior:run(dt * self.behaviorTickRate)
    end
    BGroup:updateGroups()

    updateAnimation()
    if self.probe then
    animator.setAnimationState("body", "idle")
    else
    animator.setAnimationState("body", "probeless")
    end

    if not self.rotated and self.rotation then
      mcontroller.setRotation(0)
      animator.resetTransformationGroup(self.rotationGroup)
      self.rotation = nil
      self.rotationGroup = nil
    end

    self.interacted = false
    self.damaged = false
    self.stunned = false
    self.notifications = {}

    setDamageSources()
    setPhysicsForces()
    monster.setDamageParts(self.damageParts)
    overrideCollisionPoly()
  end
  self.behaviorTick = self.behaviorTick + 1
  followOwner()
  --if self.lastHealth ~= status.resourcePercentage("health") then
  --    self.lastHealth = status.resourcePercentage("health")
  --end
  if self.childId then
  if not world.entityExists(self.childId) then
        if status.resourcePercentage("health") > 0 then
      --spawnSegment(self.size)
      end
  else
      if world.entityType(self.childId) ~= config.getParameter("bodySegment") and world.entityType(self.childId) ~= config.getParameter("tailSegment") then
      --spawnSegment(self.size)
      end
  end
  else
      --spawnSegment(self.size)
  end
end

function skillBehaviorConfig()
  local skills = config.getParameter("skills", {})
  local skillConfig = {}

  for _,skillName in pairs(skills) do
    local skillHostileActions = root.monsterSkillParameter(skillName, "hostileActions")
    if skillHostileActions then
      construct(skillConfig, "hostileActions")
      util.appendLists(skillConfig.hostileActions, skillHostileActions)
    end
  end

  return skillConfig
end

function interact(args)
  self.interacted = true
  self.board:setEntity("interactionSource", args.sourceId)
end

function shouldDie()
    
    return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
  sendHealthChild(0)
  sendHealthOwner(0)
    if not capturable.justCaptured then
    if self.deathBehavior then
      self.deathBehavior:run(script.updateDt())
    end
    capturable.die()
  end
  spawnDrops()
end

function uninit()
  BGroup:uninit()
end

function setDamageSources()
  local partSources = {}
  for part,ds in pairs(config.getParameter("damageParts", {})) do
    local damageArea = animator.partPoly(part, "damageArea")
    if damageArea then
      ds.poly = damageArea
      table.insert(partSources, ds)
    end
  end

  local damageSources = util.mergeLists(partSources, self.damageSources:values())
  damageSources = util.map(damageSources, function(ds)
    ds.damage = ds.damage * root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier")
    if ds.knockback and type(ds.knockback) == "table" then
      ds.knockback[1] = ds.knockback[1] * mcontroller.facingDirection()
    end

    local team = entity.damageTeam()
    ds.team = { type = ds.damageTeamType or team.type, team = ds.damageTeam or team.team }

    return ds
  end)
  monster.setDamageSources(damageSources)
end

function setPhysicsForces()
  local regions = util.map(self.forceRegions:values(), function(region)
    if region.type == "RadialForceRegion" then
      region.center = vec2.add(mcontroller.position(), region.center)
    elseif region.type == "DirectionalForceRegion" then
      if region.rectRegion then
        region.rectRegion = rect.translate(region.rectRegion, mcontroller.position())
        util.debugRect(region.rectRegion, "blue")
      elseif region.polyRegion then
        region.polyRegion = poly.translate(region.polyRegion, mcontroller.position())
      end
    end

    return region
  end)

  monster.setPhysicsForces(regions)
end

function overrideCollisionPoly()
  local collisionParts = config.getParameter("collisionParts", {})

  for _,part in pairs(collisionParts) do
    local collisionPoly = animator.partPoly(part, "collisionPoly")
    if collisionPoly then
      -- Animator flips the polygon by default
      -- to have it unflipped we need to flip it again
      if not config.getParameter("flipPartPoly", true) and mcontroller.facingDirection() < 0 then
        collisionPoly = poly.flip(collisionPoly)
      end
      mcontroller.controlParameters({collisionPoly = collisionPoly, standingPoly = collisionPoly, crouchingPoly = collisionPoly})
      break
    end
  end
end

function setupTenant(...)
  require("/scripts/tenant.lua")
  tenant.setHome(...)
end
function followOwner()
  if world.entityExists(self.ownerId) then
    local toBoss2 = world.magnitude(world.entityPosition(self.ownerId), mcontroller.position()) - config.getParameter("segmentSize")
    local toBoss = {toBoss2, toBoss2}
  local bossPosition = world.entityPosition(self.ownerId)
  local angleToBoss = vec2.angle(world.distance(bossPosition, mcontroller.position()))
  local calculatedAngle = {math.cos(angleToBoss), math.sin(angleToBoss)}
  local posChange = vec2.mul(vec2.mul(toBoss,calculatedAngle), {1, 1})
  mcontroller.setPosition(vec2.add(mcontroller.position(), posChange))
  mcontroller.setVelocity({0, 0})
  mcontroller.setRotation(angleToBoss)
  animator.resetTransformationGroup("body")
  animator.rotateTransformationGroup("body", angleToBoss)
  world.debugLine(mcontroller.position(), bossPosition, "red")
    if config.getParameter("flip") then
      local flip = mcontroller.rotation() > 1.5708 and mcontroller.rotation() < 4.71239  
      local anim = config.getParameter("flip")
      if flip then
          animator.setAnimationState("body", anim)
      else
          animator.setAnimationState("body", "idle")
      end
  end
  else
     status.setResourcePercentage("health", 0) 
  end
end
function setVariables(ownerId, count, headId)
    self.ownerId = ownerId
    self.headId = headId
    --self.size = count
    --spawnSegment(count, headId)
end
function sendHealthOwner(health)
    world.sendEntityMessage(self.ownerId, "healthOwner", health)
end
function sendHealthChild(health)
    world.sendEntityMessage(self.childId, "healthChild", health)
end
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end
function updateO(health)
    self.ownerHealth = health
    if health == 0 then
        status.setResourcePercentage("health", 0)
    end
end
function setHealth(health)
    self.lastHealth = health
    status.setResourcePercentage("health", health)
    if not self.probeHealthInit then
        self.probeHealth = math.random(0, round(status.resourcePercentage("health") * status.resourceMax("health")))
        self.probeHealthInit = true
    end
    if status.resourcePercentage("health") * status.resourceMax("health") < self.probeHealth then
          if self.probe then
                if status.resourcePercentage("health") > 0.01 then
              --releaseProbe()
                end
          end
      end
end
