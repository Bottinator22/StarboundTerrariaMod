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

function spawnPart(part, offset, posoffset)
    local ownerId = entity.id()
    local handId = world.spawnMonster(part, vec2.add(mcontroller.position(), posoffset), { level = monster.level(), offset = offset, ownerId = ownerId, startingOffset=posoffset })
    table.insert(self.children, handId)
end
function spawnEffectPart(part)
    local ownerId = entity.id()
    world.spawnMonster(part, mcontroller.position(), { level = monster.level(), ownerId = ownerId })
end
local deathtimer = 0
local randomsoundtimer = 0
local life = 0
local alive = true
local secondPhase = false
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
  self.shouldDie = true
  self.targetId = nil
  self.queryRange = 100
  self.keepTargetInRange = 250
  self.targets = {}
  self.targetPos = mcontroller.position()
  self.outOfSight = {}
  self.phase = "default" -- default, charging
  self.phaseTime = 0
  self.maxSpeed = 25
  self.notifications = {}
  self.approachSpeed = 5
  storage.spawnTime = world.time()
  if not storage.oldWorldInvuln then -- storage so it doesn't reset upon reload (as if you'd do that when this boss is spawned)
      local invuln = world.getProperty("invinciblePlayers")
      if invuln then
          storage.oldWorldInvuln = invuln
          --world.setProperty("invinciblePlayers", false) -- this is permanent, so the moonlord makes sure to set it back after it despawns
      end
  end
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
  
  monster.setAggressive(true)

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
    stopMusic()
    end)

  local deathBehavior = config.getParameter("deathBehavior")
  if deathBehavior then
    self.deathBehavior = behavior.behavior(deathBehavior, config.getParameter("behaviorConfig", {}), _ENV, self.behavior:blackboard())
  end

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false

  monster.setDamageBar("Special")

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  -- body parts
  spawnPart("moonlordhand", 1, {30, 10})
  spawnPart("moonlordhand", -1, {-30, 10})
  spawnPart("moonlordhead", 0, {0, 15})
  
  -- misc
  world.spawnProjectile("moonlordeffectapplier", mcontroller.position(), entity.id(), {0, 0}, false, {ownerId = entity.id()})
  
  -- graphical effects
  spawnEffectPart("moonlordbackground")
end

function stopMusic()
end
function update(dt)
    life = life + 1
    if life == 2 then
        animator.playSound("spawn")
    end
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  if not secondPhase then
    local totalhealth = 0
    local totalmaxhealth = 0
    for k,v in next, self.children do
      local health = world.entityHealth(v)
      totalhealth = totalhealth + health[1]
      totalmaxhealth = totalmaxhealth + health[2]
    end
    local healthperc = totalhealth / totalmaxhealth
    if healthperc <= 0 then
        status.setResourcePercentage("health", 1)
        secondPhase = true
        animator.setAnimationState("core", "open")
        status.removeEphemeralEffect("invulnerable")
    else
        status.setResourcePercentage("health", healthperc)
        status.addEphemeralEffect("invulnerable", 1)
    end
  else
      
  end
  if status.resourcePercentage("health") == 0 and secondPhase then
        stopMusic()
    end
    monster.setAggressive(true)
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

  monster.setDamageOnTouch(false)
  if #self.targets == 0 then
    local newTargets = world.entityQuery(mcontroller.position(), self.queryRange, {includedTypes = {"player","npc", "monster"}})
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
    if not self.targetId or not entity.isValidTarget(targetId) then
        table.remove(self.targets, 1)
        self.targetId = nil
    end

    if not self.targetId then
      self.outOfSight[targetId] = nil
    end
  until #self.targets <= 0 or self.targetId
  -- player music
  local players = world.playerQuery(mcontroller.position(), self.queryRange * 2)
  for _,entityId in pairs(players) do
      local pos = world.entityPosition(entityId)
      local dis = world.magnitude(pos, mcontroller.position())
      if dis < self.queryRange then
          world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=self.queryRange,priority=monster.level() + 10})
      end
    end
    if #players <= 0 then
        deathtimer = 1000
        animator.playSound("spawn")
    end
    self.behaviorTick = self.behaviorTick + 1
    if alive then
      if secondPhase and not status.resourcePositive("health") then
          alive = false
          animator.playSound("death")
      else
          randomsoundtimer = randomsoundtimer + 1
          if randomsoundtimer > 480 then
              animator.playSound("random")
              randomsoundtimer = 0
          end
      end
  else
      deathtimer = deathtimer + 1
      if world.magnitude(mcontroller.velocity(), {0, 0}) > 2 then
        local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
        local new = vec2.withAngle(angle, 2)
        mcontroller.setVelocity(new)
      end
      return
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
  return deathtimer > 615
end

function die()
    if not capturable.justCaptured then
    if self.deathBehavior then
      self.deathBehavior:run(script.updateDt())
    end
    capturable.die()
  end
  spawnDrops()
  stopMusic()
end

function uninit()
  BGroup:uninit()
  stopMusic()
  if storage.oldWorldInvuln then
     world.setProperty("invinciblePlayers", storage.oldWorldInvuln)
  end
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
function move()
    if self.targetId == nil then
        self.targetPos = {mcontroller.xPosition(), 0}
    else
        self.targetPos = vec2.add(world.entityPosition(self.targetId), {0, -5})
    end
    local decel = 0.9
    local dir = vec2.angle(world.distance(self.targetPos, mcontroller.position()))
    local approach = {math.cos(dir), math.sin(dir)}
    local toTarget = vec2.mul(approach,self.approachSpeed)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > self.maxSpeed then
      local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
      local approach = {math.cos(angle), math.sin(angle)}
      local new = vec2.mul(approach, self.maxSpeed)
      mcontroller.setVelocity(new)
    end
end
