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
require "/scripts/actions/terra_spawnLeveled.lua"
local offset = 0
local open = true
local phase = 0
local phasetimer = 0
function spawnArm()
    local ownerId = entity.id()
    local armId = world.spawnMonster("moonlordarm", mcontroller.position(), { level = monster.level(), ownerId = ownerId, headId = self.ownerId, offset = {offset, -50}, shoulderOffset = {offset * 13.25, 2.5} })
    table.insert(self.children, armId)
end
function spawnEye()
    local ownerId = self.ownerId
    world.spawnMonster("trueeocthulhu", mcontroller.position(), { level = monster.level(), ownerId = ownerId })
end
function openEye()
    if not open then
        animator.setAnimationState("hand", "opening")
    end
    open = true
end
function closeEye()
    if open then
        animator.setAnimationState("hand", "closing")
    end
    open = false
end
local ownerOffset = {0, 0}
local targetOwnerOffset = {0, 0}
local ownerOffsetVel = {0, 0}
local alive = true
-- not actually used for a beam, just used for phantasmal eyes
local beamAngle = 0
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
  self.shouldDie = false
  self.targetId = nil
  self.ownerPhase = "default"
  self.queryRange = 100
  self.keepTargetInRange = 250
  offset = config.getParameter("offset", 1)
  ownerOffset = config.getParameter("startingOffset")
  targetOwnerOffset = ownerOffset
  self.targets = {}
  self.targetPos = mcontroller.position()
  self.outOfSight = {}
  self.phase = "default"
  self.phaseTime = config.getParameter("phaseTime", 0)
  self.maxSpeed = 10
  self.notifications = {}
  self.ownerId = config.getParameter("ownerId")
  self.approachSpeed = 0.1
  message.setHandler("phase", function (_, _, phase)
        self.ownerPhase = phase
        for _,entityId in pairs(self.children) do
            world.sendEntityMessage(entityId, "phase", phase)
        end
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
  
  monster.setAggressive(true)

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
  
  spawnArm()
end
function update(dt)
  if alive and not status.resourcePositive("health") then
      alive = false
      animator.setAnimationState("eye", "dead")
      animator.setAnimationState("hand", "open")
      open = true
      spawnEye()
      monster.setDamageBar("none")
  end
  if alive and open then
      monster.setDamageBar("default")
      status.removeEphemeralEffect("invulnerable")
  else
      monster.setDamageBar("none")
      status.addEphemeralEffect("invulnerable", 1)
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

  monster.setDamageOnTouch(not alive)
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
  return self.shouldDie
end

function die()
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
local lastPhase = 0
function doBoltPhase()
    if math.random() > 0.25 then
        lastPhase = phase
        phase = 3
    end
end
local spheres = {}
function move()
    mcontroller.controlFace(offset * -1)
    if not world.entityExists(self.ownerId) then
        self.shouldDie = true
        return
    end
    local pupilDis = 0
    local pupilDir = 0
    local pupilScale = 1
    if self.targetId ~= nil and alive then
        local attackTargetPos = world.entityPosition(self.targetId)
        world.debugLine(mcontroller.position(), world.entityPosition(self.targetId), "yellow")
        phasetimer = phasetimer + 1
        if phasetimer > 0 then
            decel = 0.8
            approachSpeed = 0
            if phase == 0 then
                closeEye()
                if phasetimer > 120 then
                    phase = 1
                    phasetimer = -60
                end
            elseif phase == 1 then
                if phasetimer == 10 then
                    targetOwnerOffset = {offset * 20, 5}
                    animator.setAnimationState("hand", "attack")
                elseif phasetimer > 10 and phasetimer <= 200 then
                    targetOwnerOffset[1] = targetOwnerOffset[1] + (offset * 5 / 30)
                    if (phasetimer - 10) % 30 == 0 then
                        table.insert(spheres, spawnLeveled.spawnProjectile("moonlordphantasmalsphere", mcontroller.position(), entity.id(), {0, 0}, false, {level = monster.level(), power=15, targetOffset={0, 10}}))
                    end
                elseif phasetimer > 200 then
                    targetOwnerOffset = {offset * 20, 10}
                    animator.setAnimationState("hand", "open")
                    if phasetimer > 220 then
                        pupilDis = 1.5
                        pupilDir = vec2.angle(world.distance(world.entityPosition(self.targetId), vec2.add(mcontroller.position(), {0, 10})))
                        for k,v in next, spheres do
                            world.sendEntityMessage(v, "launch", pupilDir)
                        end
                        spheres = {}
                        phase = 2
                        phasetimer = -60
                        doBoltPhase()
                    end
                end
            elseif phase == 2 then
                targetOwnerOffset = {offset * 30, 10}
                pupilScale = 0.75
                pupilDis = 1.5
                beamAngle = beamAngle + (math.pi * 2 / 60)
                pupilDir = beamAngle
                if phasetimer % 10 == 0 then
                    local toTarget = vec2.withAngle(pupilDir, 60)
                    spawnLeveled.spawnProjectile("moonlordphantasmaleye", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                end
                if phasetimer > 80 then
                    phase = 0
                    phasetimer = -60
                    doBoltPhase()
                end
            elseif phase == 3 then
                if phasetimer > 30 then
                    targetOwnerOffset = {offset * 30, 5}
                    pupilDis = 1.5
                    pupilDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
                    local toTarget = vec2.withAngle(pupilDir, 240)
                    if phasetimer == 40 then
                        animator.playSound("shoot")
                        spawnLeveled.spawnProjectile("moonlordphantasmalbolt", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                    elseif phasetimer == 50 then
                        spawnLeveled.spawnProjectile("moonlordphantasmalbolt", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                    end
                    if phasetimer > 130 then
                        phase = lastPhase
                        phasetimer = -60
                    end
                end
            end
        else
            targetOwnerOffset = {offset * 20, 10}
            pupilDis = 1.5
            pupilDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
            beamActive = false
            if phasetimer > -10 and phase ~= 0 then
                openEye()
            else
                closeEye()
            end
        end
    else
        targetOwnerOffset = {offset * 20, 5}
        phase = 0
        phasetimer = 0
        if alive then
            closeEye()
        else
            openEye()
        end
    end
    local ownerPos = world.entityPosition(self.ownerId)
    local dir = vec2.angle(vec2.sub(targetOwnerOffset, ownerOffset))
    local toTarget = vec2.withAngle(dir,self.approachSpeed)
    ownerOffsetVel = vec2.add(vec2.mul(ownerOffsetVel, 0.7), toTarget)
    if vec2.mag(ownerOffsetVel) > self.maxSpeed then
      local angle = vec2.angle(ownerOffsetVel)
      local new = vec2.withAngle(angle, self.maxSpeed)
      ownerOffsetVel = new
    end
    ownerOffset = vec2.add(ownerOffset, ownerOffsetVel)
    mcontroller.setPosition(vec2.add(ownerPos, ownerOffset))
    mcontroller.setVelocity({0, 0})
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
    animator.resetTransformationGroup("pupil")
    animator.resetTransformationGroup("pupilscale")
    animator.resetTransformationGroup("pupilflip")
    animator.scaleTransformationGroup("pupilscale", pupilScale)
    animator.translateTransformationGroup("pupil", vec2.withAngle(pupilDir, pupilDis))
    animator.scaleTransformationGroup("pupilflip", {offset * -1, 1})
end
