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
local expertMode = false
function spawnTentacle()
    local mownerId = entity.id()
    world.sendEntityMessage(world.spawnMonster("planteratentacle", mcontroller.position(), { level = self.mLevel, ownerId = mownerId }), "damageTeam", entity.damageTeam())
end
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
  self.inGround = false
  self.shouldDie = true
  self.targetId = nil
  self.queryRange = 100
  self.barrageSpeed = 0
  self.keepTargetInRange = 250
  self.parent = config.getParameter("ownerId")
  self.targets = {}
  self.targetPos = mcontroller.position()
  self.outOfSight = {}
  self.status = "undefined" -- undefined, moving, latched
  self.summonTime = 0
  self.chargeDelay = 0
  self.secondPhase = false
  self.maxSpeed = 25
  self.speen = 0
  self.notifications = {}
  self.approachSpeed = 1
  self.allowBackgroundLatch = false
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
    stopMusic()
    end)
  message.setHandler("setTarget", function (_,_,pos)
                     self.targetPos = pos
                     end)
  message.setHandler("secondPhase", function ()
                     self.secondPhase = true
                    if expertMode then
                        for i=1,3,1 do
                            spawnTentacle()
                        end
                    end
                     end)
  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
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
end

function stopMusic()
    return
end
function update(dt)
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  monster.setAggressive(false)
  monster.setDamageOnTouch(true)
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
      monster.setDamageOnTouch(false)
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
  move()
  self.behaviorTick = self.behaviorTick + 1
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
function math.round(num)
    return math.floor(num+0.5)
end
function move()
    if not world.entityExists(self.parent) then
        status.setResourcePercentage("health", 0)
        return
    end
    self.parentPos = world.entityPosition(self.parent)
    local mag = world.magnitude(mcontroller.position(), self.parentPos)
    local dis = world.distance(self.parentPos, mcontroller.position())
    world.debugLine(mcontroller.position(), self.parentPos, "green")
    local dir = vec2.angle(dis)
    animator.resetTransformationGroup("beam")
    animator.scaleTransformationGroup("beam", mag)
    animator.rotateTransformationGroup("beam", dir)
    mcontroller.setRotation(dir + math.pi)
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", dir + math.pi)
    if self.status == "undefined" then
        self.status = "moving"
    end
    world.debugLine(mcontroller.position(), self.targetPos, "red")
    if world.magnitude(self.targetPos, mcontroller.position()) <= 0.1 then
        self.approachSpeed = 0
        if self.status == "moving" then
            self.status = "latched"
            animator.setAnimationState("body","latching")
        end
    else
        self.approachSpeed = math.min(world.magnitude(self.targetPos, mcontroller.position()) * 10, 20)
        if self.secondPhase then
            self.approachSpeed = math.min(world.magnitude(self.targetPos, mcontroller.position()) * 10, 40)
        end
        if self.status == "latched" then
            self.status = "moving"
            animator.setAnimationState("body","unlatching")
        end
    end
    self.allowBackgroundLatch = self.secondPhase
    if not self.allowBackgroundLatch then
        local rect = {mcontroller.xPosition() - 0.5, mcontroller.yPosition() - 0.5, mcontroller.xPosition() + 0.5, mcontroller.yPosition() + 0.5}
        self.inGround = world.rectCollision(rect, {"Block"})
    else
        local myposRounded = {math.round(mcontroller.xPosition()),math.round(mcontroller.yPosition())}
        self.inGround = world.tileIsOccupied(myposRounded, true) or world.tileIsOccupied(myposRounded, false)
    end
    local dir = vec2.angle(world.distance(self.targetPos, mcontroller.position()))
    local approach = {math.cos(dir), math.sin(dir)}
    local toTarget = vec2.mul(approach,self.approachSpeed)
    mcontroller.setVelocity(toTarget)
    --mag = mag - 400 -- force hooks to never go this far
    --if mag > 0 then
    --    local toParent = {mag, mag}
    --    local dis = world.distance(self.parentPos, mcontroller.position())
    --    local angle = vec2.angle(dis)
    --    local calculatedAngle = {math.cos(angle), math.sin(angle)}
    --    local posChange = vec2.mul(toParent,calculatedAngle)
    --    mcontroller.setPosition(vec2.add(mcontroller.position(), posChange))
    --    mcontroller.setVelocity({0, 0})
    --    self.targetPos = mcontroller.position()
    --end
    local sendstatus = self.status
    if self.status == "latched" and not self.inGround then
        sendstatus = "invalid"
    end
    world.debugText(sendstatus, mcontroller.position(), "yellow")
    world.sendEntityMessage(self.parent, "hookupdate", entity.id(), sendstatus)
end
