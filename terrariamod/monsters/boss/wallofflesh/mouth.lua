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
require "/scripts/actions/terra_rotateUtil.lua"
function spawnEye(offset)
    local ownerId = entity.id()
    local handId = world.spawnMonster("wallofflesheye", mcontroller.position(), { level = monster.level(), ownerId = ownerId, offset=offset })
    table.insert(self.children, handId)
end
function spawnLeech()
    local ownerId = entity.id()
    local handId = world.spawnMonster("leechhead", mcontroller.position(), { level = monster.level(), ownerId = ownerId })
end
function spawnHungry(pos) -- pos is offset from head
    local ownerId = entity.id()
    local handId = world.spawnMonster("thehungry", mcontroller.position(), { level = monster.level(), ownerId = ownerId, anchorPoint=pos})
end
local wallId
local moveDir = 0
local approachSpeed
local summons = 0
local top = 0
local bottom = 0
local lastHealth = 1
local hasRoared = false
local tongueTarget = nil
local tongueId = nil
local tonguePosition = {0, 0}
local tongueUpdateTime = 0
local tongueMaxRange = 250
local tongueMinRange = 75
local tongueSpeed = 0.5
local tongueDoneTimer = 0
local life = 0
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
self.baseTurnSpeed = 0.1
  self.shouldDie = true
  self.targetId = nil
  self.queryRange = 100
  self.keepTargetInRange = 250
  self.targets = {}
  self.targetPos = mcontroller.position()
  mcontroller.setRotation(0)
  self.outOfSight = {}
  self.phase = "default" -- default, charging
  self.phaseTime = 0
  self.summonTime = 1000
  self.chargeDelay = 0
  self.secondPhase = false
  self.secondPhaseTrig = false
  self.maxSpeed = 10
  self.speen = 0
  self.notifications = {}
  lastHealth = status.resourcePercentage("health")
  approachSpeed = 10
  storage.spawnTime = world.time()
  message.setHandler("health", function(_,_,health,id)
        status.setResourcePercentage("health", health)
        lastHealth = health
        for k, eyeId in pairs(self.children) do
            if eyeId ~= id then
                    world.sendEntityMessage(eyeId, "health", health)
            end
        end
  end)
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
        lastHealth = status.resourcePercentage("health")
        sendHealth(lastHealth)
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
  
  monster.setAggressive(true)

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  spawnEye(0.5)
  spawnEye(-0.5)
  wallId = world.spawnMonster("walloffleshwall", mcontroller.position(), { level = monster.level(), ownerId = entity.id() })
  local hungryCount = 15
  local hungrySpacing = 7.5
  local bottomHungryY = hungrySpacing * hungryCount * -0.5
  for i = 0,hungryCount - 1 do
      spawnHungry({0, bottomHungryY + hungrySpacing * i})
  end
end
function takeDamage(damageRequest)
    status.applySelfDamageRequest(damageRequest)
end
function sendHealth(health)
        for k, eyeId in pairs(self.children) do
            if eyeId ~= id then
                    world.sendEntityMessage(eyeId, "health", health)
            end
        end
end
function stopMusic()
end
function update(dt)
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  if status.resourcePercentage("health") ~= lastHealth then
      lastHealth = status.resourcePercentage("health")
      sendHealth(lastHealth)
  end
  if status.resourcePercentage("health") == 0 then
        stopMusic()
    end
  capturable.update(dt)
  self.damageTaken:update()

  if status.resourcePositive("stunned") then
    animator.setGlobalTag("hurt", "hurt")
    self.stunned = true
    mcontroller.clearControls()
    if self.damaged then
      self.suppressDamageTimer = config.getParameter("stunDamageSuppression", 0.5)
      --monster.setDamageOnTouch(false)
    end
    return
  else
    animator.setGlobalTag("hurt", "")
    animator.setAnimationState("damage", "none")
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
  life = life + 1
  if self.targetId then
      if moveDir == 0 then
          moveDir = math.max(math.min(world.entityPosition(self.targetId)[1] - mcontroller.xPosition(), 1), -1)
      end
      if not hasRoared then
          if life > 5 then
            animator.playSound("roar")
            hasRoared = true
          end
      end
  end
  move()
  tongue()
  self.behaviorTick = self.behaviorTick + 1
  monster.setDamageOnTouch(true)
  -- player music
  local players = world.playerQuery(mcontroller.position(), self.queryRange * 2)
  for _,entityId in pairs(players) do
      local pos = world.entityPosition(entityId)
      local dis = world.magnitude(pos, mcontroller.position())
      if dis < self.queryRange then
          world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=self.queryRange,priority=monster.level() + 10})
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
function isValidTongueTarget(target)
    if not entity.isValidTarget(target) then
        return false
    elseif (world.entityPosition(target)[1] - mcontroller.xPosition() < 0) ~= (moveDir < 0) then
        return true
    elseif world.magnitude(world.entityPosition(target), mcontroller.position()) < tongueMinRange then
        return false
    end
    return true
end
function makeCirclePoly(radius, x, y)
    local output = {}
    local points = 360
    for i = 1, points, 1 do
        local angle = (math.pi * 2) / points * i
        output[i] = {(math.cos(angle) * radius) + x, (math.sin(angle) * radius) + y}
    end
    return output
end
function tongue()
    if not tongueTarget or not world.entityExists(tongueTarget) then
        if tongueId then
            if world.entityExists(tongueId) then
                world.sendEntityMessage(tongueId, "die") -- kill the tongue projectile
                tongueId = nil
            end
        end
        animator.resetTransformationGroup("beam")
        animator.scaleTransformationGroup("beam", 0) -- hide the tongue
        tongueUpdateTime = tongueUpdateTime + 1
        if tongueUpdateTime > 10 then
            tongueUpdateTime = 0
            local targets = world.entityQuery(mcontroller.position(), tongueMaxRange, {includedTypes = {"player","npc", "monster"}})
            table.sort(targets, function(a, b)
                return world.magnitude(world.entityPosition(a), mcontroller.position()) > world.magnitude(world.entityPosition(b), mcontroller.position())
            end)
            for k,target in pairs(targets) do
                if isValidTongueTarget(target) then
                    tongueTarget = target
                    tonguePosition = world.entityPosition(tongueTarget)
                    tongueDoneTimer = 0
                    break
                end
            end
        end
    elseif not tongueId or not world.entityExists(tongueId) then
        tongueId = world.spawnProjectile("walloffleshtongue", world.entityPosition(tongueTarget), entity.id(), {0, 0}, false, {ownerId=entity.id()})
    elseif tongueDoneTimer < 10 then
        world.sendEntityMessage(tongueId, "move", world.entityPosition(tongueTarget))
        world.sendEntityMessage(tongueTarget, "move", tonguePosition)
        local targetPosition = {mcontroller.xPosition() + 10 * moveDir,mcontroller.yPosition()}
        if world.magnitude(targetPosition, tonguePosition) < tongueSpeed then
            tonguePosition = targetPosition
            tongueDoneTimer = tongueDoneTimer + 1
        else
            tongueDoneTimer = 0
            local targetAngle = vec2.angle(world.distance(targetPosition, tonguePosition))
            local approach = {math.cos(targetAngle), math.sin(targetAngle)}
            local toTarget = vec2.mul(approach,tongueSpeed)
            tonguePosition = vec2.add(tonguePosition, toTarget)
        end
        -- show the graphical tongue latching on to them
        local mag = world.magnitude(mcontroller.position(), tonguePosition)
        local dis = world.distance(tonguePosition, mcontroller.position())
        local dir = vec2.angle(dis)
        animator.resetTransformationGroup("beam")
        animator.scaleTransformationGroup("beam", mag)
        animator.rotateTransformationGroup("beam", dir)
    else
        world.sendEntityMessage(tongueId, "die") -- kill the tongue projectile
        tongueTarget = nil
        tongueId = nil
        animator.resetTransformationGroup("beam")
        animator.scaleTransformationGroup("beam", 0) -- hide the tongue
    end
    world.debugPoly(makeCirclePoly(tongueMinRange, mcontroller.xPosition(), mcontroller.yPosition()), "green")
    world.debugPoly(makeCirclePoly(tongueMaxRange, mcontroller.xPosition(), mcontroller.yPosition()), "red")
end
function roundVector(v)
    return {math.floor(v[1]+0.5),math.floor(v[2]+0.5)}
end
function defaultMove()
    if self.targetId then
        local targetPos = world.entityPosition(self.targetId)
        local targetDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
        local myDir = mcontroller.rotation()
        local diff = rotateUtil.getRelativeAngle(targetDir, myDir)
        mcontroller.setRotation(rotateUtil.slowRotate(myDir, diff, self.baseTurnSpeed))
        local myPos = roundVector(mcontroller.position())
        top = world.lineTileCollisionPoint(myPos, {myPos[1], myPos[2] + 200}, {"Block"})
        bottom = world.lineTileCollisionPoint(myPos, {myPos[1], myPos[2] - 200}, {"Block"})
        world.debugLine(myPos, {myPos[1], myPos[2] + 200}, "blue")
        world.debugLine(myPos, {myPos[1], myPos[2] - 200}, "blue")
        if top then
            top = top[1]
        else
            top = {myPos[1], myPos[2] + 200}
        end
        world.debugLine({top[1] - 5, top[2]}, {top[1] + 5, top[2]}, "green")
        if bottom then
            bottom = bottom[1]
        else
            bottom = {myPos[1], math.max(myPos[2] - 200, 0)}
        end
        world.debugLine({bottom[1] - 5, bottom[2]}, {bottom[1] + 5, bottom[2]}, "green")
        self.targetPos = myPos
        self.targetPos[2] = (top[2] + bottom[2]) / 2
        world.debugLine({self.targetPos[1] - 5, self.targetPos[2]}, {self.targetPos[1] + 5, self.targetPos[2]}, "yellow")
        self.summonTime = self.summonTime - 1
        local summonBurstCount = 7 - 4 * status.resourcePercentage("health")
        if self.summonTime <= 0 then
            self.summonTime = 100
            if summons >= summonBurstCount then
                self.summonTime = 100 + 1400 * status.resourcePercentage("health")
                summons = 0
            else
                summons = summons + 1
                spawnLeech()
                animator.playSound("summon")
            end
        end
    end
end
function move()
    defaultMove()
    local vertMovement = math.min(math.max(self.targetPos[2] - mcontroller.yPosition(), approachSpeed * -1), approachSpeed)
    mcontroller.setVelocity({moveDir * (3 - 1 * status.resourcePercentage("health")), vertMovement})
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
    local state = {targetPos = self.targetPos, top=top, bottom=bottom, moveDir=moveDir, vertMovement=vertMovement}
    world.sendEntityMessage(wallId, "state", state)
    for k,eyeId in pairs(self.children) do
        world.sendEntityMessage(eyeId, "state", state)
    end
end
