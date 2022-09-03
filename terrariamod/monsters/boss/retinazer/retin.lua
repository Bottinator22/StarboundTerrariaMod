require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/drops.lua"
require "/scripts/status.lua"
require "/scripts/tenant.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/actions/terra_spawnLeveled.lua"
require "/scripts/actions/terra_rotateUtil.lua"
function spawnMinion()
    local ownerId = entity.id()
    local handId = world.spawnMonster("socthulhu", mcontroller.position(), { level = monster.level(), ownerId = ownerId })
    table.insert(self.children, handId)
end
local expertMode = false
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
  self.shouldDie = true
  self.targetId = nil
  self.queryRange = 100
  self.barrageSpeed = 0
  self.keepTargetInRange = 250
  self.targets = {}
  self.targetPos = mcontroller.position()
  self.outOfSight = {}
  self.phase = "default" -- default, charging
  self.phaseTime = 0
  self.summonTime = 0
  self.chargeDelay = 0
  self.secondPhase = false
  self.secondPhaseTrig = false
  self.maxSpeed = 25
  self.speen = 0
  self.notifications = {}
  self.approachSpeed = 2
  self.parent = config.getParameter("ownerId", -1)
  expertMode = config.getParameter("expertMode", false)
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
  
  monster.setAggressive(true)

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

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  if world.entityExists(self.parent) then
      message.setHandler("pet.attemptCapture", function(_,_,...)
                        return world.callScriptedEntity(self.parent, "capturable.attemptCapture", ...)
                         end)
  end
end

function stopMusic()
end
function update(dt)
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  if status.resourcePercentage("health") == 0 then
        stopMusic()
    end
    if not world.entityExists(self.parent) then
        monster.setDamageBar("Special")
    end
  capturable.update(dt)
  self.damageTaken:update()

  if status.resourcePositive("stunned") then
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

  monster.setDamageOnTouch(true)

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
  move()
  self.behaviorTick = self.behaviorTick + 1
  -- player music
  local players = world.playerQuery(mcontroller.position(), self.queryRange * 2)
  for _,entityId in pairs(players) do
      local pos = world.entityPosition(entityId)
      local dis = world.magnitude(pos, mcontroller.position())
      if dis < self.queryRange then
          world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=self.queryRange,priority=monster.level() + 10})
      end
    end
    for _,entityId in pairs(self.children) do
        if world.entityExists(entityId) then
            world.sendEntityMessage(entityId, "phase", self.phase)
        end
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
function defaultMove(barrage)
    self.targetPos = world.entityPosition(self.targetId)
    self.maxSpeed = 25
    local targetDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
    local myDir = mcontroller.rotation()
    local diff = rotateUtil.getRelativeAngle(targetDir, myDir)
    mcontroller.setRotation(rotateUtil.slowRotate(myDir, diff, 0.1))
    local myXDiff = mcontroller.xPosition() - self.targetPos[1]
    if barrage then
        local offset = 15
        if myXDiff < 0 then
            offset = offset * -1
        end
        self.targetPos[1] = self.targetPos[1] + offset
    elseif not self.secondPhase then
        local offset = 15
        if myXDiff < 0 then
            offset = offset * -1
        end
        self.targetPos[1] = self.targetPos[1] + offset
        self.targetPos[2] = self.targetPos[2] + 15
    else
        self.targetPos[2] = self.targetPos[2] + 15
    end
    self.approachSpeed = 3
        self.summonTime = self.summonTime + 1
        if expertMode then
            self.summonTime = self.summonTime + (0.5 - status.resourcePercentage("health") / 2)
        end
        self.barrageSpeed = 10 + 10 * status.resourcePercentage("health")
        local time = 50
        if self.secondPhase then
            time = 40
        end
        if barrage then
            time = self.barrageSpeed
        end
        if self.summonTime > time then
            self.summonTime = 0
            animator.playSound("laserShoot")
            local dir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
            local approach = {math.cos(dir), math.sin(dir)}
            local toTarget = vec2.mul(approach,1)
            if not self.secondPhase then
                spawnLeveled.spawnProjectile("bluelaser", mcontroller.position(), entity.id(), toTarget, false, {level=monster.level(), power=8})
            else
                local weak = ""
                local power = 10
                if barrage then
                    weak = "weak"
                    power = 5
                end
                spawnLeveled.spawnProjectile("redlaser"..weak, mcontroller.position(), entity.id(), toTarget, false, {level=monster.level(),power=power})
            end
        end
end
function chargeMove()
    if not self.secondPhase then
    self.targetPos = world.entityPosition(self.targetId)
    self.chargeDelay = self.chargeDelay - 1
    self.phaseTime = self.phaseTime - 1
    if self.chargeDelay <= 25 then
        local targetDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
        local myDir = mcontroller.rotation()
        local diff = rotateUtil.getRelativeAngle(targetDir, myDir)
        mcontroller.setRotation(rotateUtil.slowRotate(myDir, diff, 0.2))
    end
    if self.chargeDelay <= 0 then
        self.maxSpeed = 50
        self.approachSpeed = 100
        mcontroller.setVelocity({0, 0})
        self.chargeDelay = 60
        if expertMode then
            self.maxSpeed = 75 - (status.resourcePercentage("health") - 0.5) * 2 * 25
            self.approachSpeed = 150 - (status.resourcePercentage("health") - 0.5) * 2 * 50
            self.chargeDelay = 85 - (status.resourcePercentage("health") - 0.5) * 2 * 25
        end
        self.phaseTime = self.phaseTime + 1
    else
        self.approachSpeed = 0
    end
    else
        defaultMove(true)
    end
end
function transformMove()
    mcontroller.setRotation(mcontroller.rotation() + math.rad(self.speen))
    if self.phaseTime >= 50 then
        self.speen = self.speen - 1
        if not self.secondPhase then
            animator.setAnimationState("body","second")
            self.secondPhase = true
            animator.setLightActive("glow", true)
            animator.playSound("secondPhase")
        end
    else
        self.speen = self.speen + 1
    end
end
function move()
    if world.timeOfDay() < 0.5 then
        self.targetId = nil
    end
    if self.targetId == nil then
        self.targetPos = vec2.add(mcontroller.position(), {0, 100})
        self.approachSpeed = 1
    else
    self.phaseTime = self.phaseTime + 1
    if status.resourcePercentage("health") <= 0.5 and not self.secondPhaseTrig then
        self.phase = "transform"
        self.phaseTime = 0
        self.speen = 0
        self.secondPhaseTrig = true
    end
    local time = 400
    if self.secondPhase then
        time = status.resourcePercentage("health") * 800
    end
  if self.phaseTime > time then
        if self.phase == "default" then
            self.phase = "charge"
            self.phaseTime = 0
            self.chargeDelay = 0
            self.barrageSpeed = 50
        end
  end
  time = 5
  if self.secondPhase then
      time = 200
  end
  if self.phaseTime > time then
        if self.phase == "charge" then
            self.phase = "default"
            self.phaseTime = 0
        end
    end
    if self.phaseTime > 100 then
        if self.phase == "transform" then
            self.phase = "default"
            self.phaseTime = 500
        end
    end
    if self.phase == "charge" then
        chargeMove()
    end
    if self.phase == "default" then
        defaultMove(false)
    end
    if self.phase == "transform" then
        transformMove()
    end
    end
    if self.secondPhase then
        self.approachSpeed = 3
    end
    local decel = 0.95
    if self.phase == "charge" and not self.secondPhase then
        decel = 0.99
    end
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
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
    animator.setLightPosition("glow", vec2.mul({math.cos(mcontroller.rotation()), math.sin(mcontroller.rotation())}, 10))
end
