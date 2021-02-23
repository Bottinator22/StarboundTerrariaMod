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
self.probeHealth = math.random(0, status.resourcePercentage("health") * status.resourceMax("health"))
    self.pathing = {}
    self.fireTime = math.random(0, 250)
self.ownerId = 1
self.headId = 0
  self.targetId = nil
  self.queryRange = 100
  self.keepTargetInRange = 250
  self.targets = {}
    self.outOfSight = {}
self.size = 0
self.spawnTimer = 10
self.probe = true
self.releasingProbe = false
self.probeId = 0
self.childId = 0
self.lastHealth = 0
setHealth(config.getParameter("ownerHealth"))

    message.setHandler("healthOwner", function(_,_,health)
        setHealth(health)
        sendHealthOwner(health)
  end)
    message.setHandler("healthChild", function(_,_,health)
        setHealth(health)
        sendHealthChild(health)
  end)
  message.setHandler("setVariables", function(_,_,...)
    setVariables(...)
    end)
    message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
        --setVariables(config.getParameter("ownerId"), config.getParameter("segmentsLeft"), config.getParameter("headId"))
  end)
    message.setHandler("update", function(_, _, dt)
        followOwner()
        if world.entityExists(self.childId) then
            world.sendEntityMessage(self.childId, "update", dt)
        end
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
         self.board:setEntity("damageSource", notification.sourceEntityId)
              sendHealthOwner(status.resourcePercentage("health"))
                sendHealthChild(status.resourcePercentage("health"))
        if status.resourcePercentage("health") * status.resourceMax("health") < self.probeHealth then
          if self.probe then
            if status.resourcePercentage("health") > 0.01 then
            releaseProbe()
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

  monster.setAnimationParameter("chains", {})
end
function targeting()
      if #self.targets == 0 then
    local newTargets = world.entityQuery(mcontroller.position(), self.queryRange, {includedTypes = {"player","npc"}})
    table.sort(newTargets, function(a, b)
      return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
    end)
    for _,entityId in pairs(newTargets) do
      if true then
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

    --if self.targetId and false then
    --  local timer = self.outOfSight[targetId] or 3.0
    --  timer = timer - dt
    --  if timer <= 0 then
    --    table.remove(self.targets, 1)
    --    selftargetId = nil
    --  else
    --    self.outOfSight[targetId] = timer
    --  end
    --end

    if not self.targetId then
      self.outOfSight[targetId] = nil
    end
  until #self.targets <= 0 or self.targetId
end
function firing()
    if not self.targetId then
        return
    end
    if not world.entityExists(self.targetId) then
        return
    end
    self.fireTime = self.fireTime - 1
    if self.fireTime <= 0 then
        if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"}) then
            animator.playSound("fire")
            local dir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
            local approach = {math.cos(dir), math.sin(dir)}
            local toTarget = vec2.mul(approach,1)
            world.spawnProjectile("redlaser", mcontroller.position(), entity.id(), toTarget)
        end
        self.fireTime = 250
    end
end
function update(dt)
     mcontroller.controlFace(1)
  
  self.damageTaken:update()
  self.spawnTimer = self.spawnTimer - 1

   if status.resourcePositive("stunned") then
     if self.damaged then
       self.suppressDamageTimer = config.getParameter("stunDamageSuppression", 0.5)
       monster.setDamageOnTouch(false)
     end
  end

  -- Suppressing touch damage
  if self.suppressDamageTimer then
    monster.setDamageOnTouch(false)
    self.suppressDamageTimer = math.max(self.suppressDamageTimer - dt, 0)
    if self.suppressDamageTimer == 0 then
      self.suppressDamageTimer = nil
    end
  else
    monster.setDamageOnTouch(true)
  end
    if self.releasingProbe then
        if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"}) then -- don't spawn probes in blocks
        if self.probe then
            trueReleaseProbe()
        end
        end
    end
    if self.probe then
    animator.setAnimationState("body", "idle")
    else
    animator.setAnimationState("body", "probeless")
    end
    --setDamageSources()
    if self.probe then
        targeting()
        firing()
    end
  --followOwner()
  if self.lastHealth ~= status.resourcePercentage("health") then
      self.lastHealth = status.resourcePercentage("health")
      sendHealthOwner(status.resourcePercentage("health"))
      sendHealthChild(status.resourcePercentage("health"))
      if status.resourcePercentage("health") * status.resourceMax("health") < self.probeHealth then
          if self.probe then
          releaseProbe()
          end
      end
  end
  if self.childId then
  if not world.entityExists(self.childId) then
      if status.resourcePercentage("health") > 0 then
      spawnSegment(self.size)
      end
  else
      if world.entityType(self.childId) ~= "wormbossbody" and world.entityType(self.childId) ~= "wormbosstail" then
      --spawnSegment(self.size)
      end
  end
  end
end

function skillBehaviorConfig()
  local skills = config.getParameter("skills", {})
  local skillConfig = {}
    if self.probe then
  for _,skillName in pairs(skills) do
    local skillHostileActions = root.monsterSkillParameter(skillName, "hostileActions")
    if skillHostileActions then
      construct(skillConfig, "hostileActions")
      util.appendLists(skillConfig.hostileActions, skillHostileActions)
    end
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
  if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"}) then
    spawnDrops()
  end
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
    local toBoss2 = world.magnitude(world.entityPosition(self.ownerId), mcontroller.position()) - 2.5
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
  else
     if self.spawnTimer > 0 then
         mcontroller.setPosition({0, 0})
     end
      status.setResourcePercentage("health", 0) 
  end
end
function setVariables(ownerId, count, headId)
    self.ownerId = ownerId
    self.headId = headId
    self.size = count
    spawnSegment(count, headId)
end
function sendHealthOwner(health)
    world.sendEntityMessage(self.ownerId, "healthOwner", health)
end
function sendHealthChild(health)
    world.sendEntityMessage(self.childId, "healthChild", health)
end
function setHealth(health)
    self.lastHealth = health
    status.setResourcePercentage("health", health)
    if status.resourcePercentage("health") * status.resourceMax("health") < self.probeHealth then
          if self.probe then
          releaseProbe()
          end
      end
end
function spawnSegment(count)
    if (count > 0) then
    local segments = {}
    local ownerId = entity.id()
  local stepAngle = (math.pi * 2) / count
    local offset = vec2.rotate({1,0}, stepAngle * 1)
    local segmentId = world.spawnMonster("wormbossbody", vec2.add(mcontroller.position(), offset), { level = monster.level(),ownerHealth = status.resourcePercentage("health")})
    table.insert(segments, segmentId)
    world.sendEntityMessage(segmentId, "setVariables", ownerId, count - 1, headId)
    self.childId = segmentId

  return true, {segments = segments}, segmentID
    else
    local segments = {}
    local ownerId = entity.id()
  local stepAngle = (math.pi * 2) / count
    local offset = vec2.rotate({1,0}, stepAngle * 1)
    local segmentId = world.spawnMonster("wormbosstail", vec2.add(mcontroller.position(), offset), { level = monster.level(),ownerHealth = status.resourcePercentage("health")})
    table.insert(segments, segmentId)
    world.sendEntityMessage(segmentId, "setVariables", ownerId, 0, headId)
    self.childId = segmentId
    end
end
function releaseProbe()
    self.releasingProbe = true
end
function trueReleaseProbe()
    self.probe = false
    self.behavior = nil
    self.probeId = world.spawnMonster("probe", mcontroller.position(), { level = monster.level()})
end
