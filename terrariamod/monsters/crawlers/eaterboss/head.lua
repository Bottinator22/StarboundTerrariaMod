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
function spawnSegment(count)
    if self.childHealth > 0 then
    local tempownerId = entity.id()
--  local stepAngle = (math.pi * 2) / count
--  local offset = vec2.rotate({1,0}, stepAngle * 1)
    local templevel = monster.level()
    if ownerId() then
        templevel = config.getParameter("capturedLevel")
    end
    local segmentId = world.spawnMonster(config.getParameter("bodySegment"), mcontroller.position(), { level = templevel,ownerHealth = status.resourcePercentage("health"),ownerId = tempownerId, segmentsLeft = count - 1, headId = tempownerId})
    self.childId = segmentId
    world.sendEntityMessage(segmentId, "damageTeam", entity.damageTeam())

  return true, segmentID
    else
        status.setResourcePercentage("health", 0)
    end
end
-- Engine callback - called on initialization of entity
function init()
    if ownerId() and config.getParameter("change") then
        status.setResourcePercentage("health", 0)
    end
    self.pathing = {}
  self.lastPosition = nil
self.childId = config.getParameter("childId")
self.lastHealth = status.resourcePercentage("health")
  self.shouldDie = true
  self.speed = 0
  self.targetId = nil
  self.inGround = true
  self.childHealth = 1
  self.queryRange = 30
  self.keepTargetInRange = 50
    self.approachSpeed = config.getParameter("speed", 1)
  self.gravity = -1
  self.targets = {}
  self.outOfSight = {}
  self.notifications = {}
      message.setHandler("healthOwner", function(_,_,health)
        updateC(health)
  end)
  message.setHandler("childChange", function(_,_,newChild)
        self.childId = newChild
  end)
        message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
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

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 5))
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
      end
    end
  end)

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
      monster.setDropPool(nil)
      monster.setDeathParticleBurst(nil)
      monster.setDeathSound(nil)
      self.deathBehavior = nil
      self.shouldDie = true
      status.addEphemeralEffect("monsterdespawn")
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
  if config.getParameter("change") then
      return
  end
      if config.getParameter("size") then
        spawnSegment(config.getParameter("size"))
      else
         spawnSegment(80) 
      end
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
  if self.lastHealth ~= status.resourcePercentage("health") then
      self.lastHealth = status.resourcePercentage("health")
      sendHealthChild(status.resourcePercentage("health"))
  end
  targets = {"player","npc"}
  if ownerId() then
  targets = {"monster","npc"}
  end
  if #self.targets == 0 then
    local newTargets = world.entityQuery(mcontroller.position(), self.queryRange, {includedTypes = targets})
    table.sort(newTargets, function(a, b)
      return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
    end)
    for _,entityId in pairs(newTargets) do
      if entity.isValidTarget(entityId) then
        table.insert(self.targets, entityId)
      end
    end
  end
  
repeat
    self.targetId = self.targets[1]
    if self.targetId == nil then break end

    local targetId = self.targetId
    if not world.entityExists(targetId)
       or world.magnitude(world.entityPosition(targetId), mcontroller.position()) > self.keepTargetInRange then
      table.remove(self.targets, 1)
      self.targetId = nil
    end
    if self.targetId and entity.isValidTarget(targetId) then
        table.remove(self.targets, 1)
        selftargetId = nil
    end

    if not self.targetId then
      self.outOfSight[targetId] = nil
    end
  until #self.targets <= 0 or self.targetId
  if world.gravity(mcontroller.position()) == 0 then
      self.inGround = true
  else
    self.inGround = world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"})
    if not self.inGround then
        if world.liquidAt({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}) then
            self.inGround = true
        end
    end
  end
    if not world.entityExists(self.childId) then
        status.setResourcePercentage("health", 0)
    end
    move()
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

function ownerId()
    if capturable.ownerUuid() then
        local playerIds = world.players()
        table.sort(playerIds, function(a)
      return world.entityUniqueId(a) == capturable.ownerUuid() end)
        return playerIds[1]
    else
        return nil
    end
end

function setupTenant(...)
  require("/scripts/tenant.lua")
  tenant.setHome(...)
end
function sendHealthChild(health)
    if world.entityExists(self.childId) then
        world.sendEntityMessage(self.childId, "healthChild", health)
    end
end
function setHealth(health)
    self.lastHealth = health
    status.setResourcePercentage("health", health)
end
function updateC(health)
    self.childHealth = health
    if health == 0 then
        status.setResourcePercentage("health", 0)
    end
end
function move()
    if self.lastPosition then
       local dif = vec2.sub(self.lastPosition, mcontroller.position())
       if math.abs(dif[1]) > 100 or math.abs(dif[2]) > 100 then -- Either moved too fast or teleported
            mcontroller.setVelocity({0, 0})
       end
   end
   self.lastPosition = mcontroller.position()
    local toTarget = {0, 0}
    if not self.targetId then
      if ownerId() then
            if world.magnitude(world.entityPosition(ownerId()), mcontroller.position()) <= 10 then
                return
            end
      else
          return
      end
  end
    local targetPosition = nil
    if ownerId() then
    if self.targetId and world.magnitude(world.entityPosition(ownerId()), mcontroller.position()) <= 50  then
        targetPosition = world.entityPosition(self.targetId)
    else
        self.targetId = nil
        if world.magnitude(world.entityPosition(ownerId()), mcontroller.position()) > 10 then
        targetPosition = world.entityPosition(ownerId())
        end
    end
    elseif self.targetId then
            targetPosition = world.entityPosition(self.targetId)
        end
    if world.magnitude(targetPosition, mcontroller.position()) > 50 then
        self.inGround = true
    end
    if self.inGround then
    if self.inGround then
        if targetPosition then
        world.debugLine(mcontroller.position(), targetPosition, "red") -- boss -> target red line
        end
    else
        world.debugLine(mcontroller.position(), {mcontroller.position()[1], 0}, "red") -- boss -> target red line
    end
    -- Rotate head
    if not targetPosition then
        mcontroller.approachVelocity({0, 0}, 10)
        mcontroller.setRotation(vec2.angle(world.distance(vec2.add(mcontroller.position(), mcontroller.velocity()), mcontroller.position())))
        animator.resetTransformationGroup("body")
        animator.rotateTransformationGroup("body", mcontroller.rotation())
        return
    end
    if targetPosition[1] < mcontroller.position()[1] then
        toTarget[1] = self.approachSpeed * -1
    else if targetPosition[1] > mcontroller.position()[1] then
        toTarget[1] = self.approachSpeed
    end
    end
    if targetPosition[2] < mcontroller.position()[2] then
        toTarget[2] = self.approachSpeed * -1
    else if targetPosition[2] > mcontroller.position()[2] then
        toTarget[2] = self.approachSpeed
    end
    end
    mcontroller.setVelocity(vec2.add(mcontroller.velocity(), toTarget))
  else 
      mcontroller.setVelocity(vec2.add(mcontroller.velocity(), {0, self.gravity})) -- Force to apply for falling
  end
  
    world.debugText(
      "current rotation: %s\ncurrent pos: %s\npi: %s\ncurrent velocity: %s\nhealth percentage: %s",
      mcontroller.rotation(),
      mcontroller.position(),
      math.rad(180),
      mcontroller.velocity(),
      status.resourcePercentage("health"),
      vec2.add(mcontroller.position(), {2, 0}), "red"
    )
  mcontroller.setRotation(vec2.angle(world.distance(vec2.add(mcontroller.position(), mcontroller.velocity()), mcontroller.position())))
  animator.resetTransformationGroup("body")
  animator.rotateTransformationGroup("body", mcontroller.rotation())
    if config.getParameter("flip") then
      local flip = mcontroller.rotation() > 1.5708 and mcontroller.rotation() < 4.71239  
      local anim = config.getParameter("flip")
      if flip then
          animator.setAnimationState("body", anim)
      else
          animator.setAnimationState("body", "idle")
      end
    end
    if mcontroller.position()[2] < 10 then
      mcontroller.setPosition({mcontroller.position()[1], 20})
      mcontroller.setVelocity({0, 0})
  end
end
 
