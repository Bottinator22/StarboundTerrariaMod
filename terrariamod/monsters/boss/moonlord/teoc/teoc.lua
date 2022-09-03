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
require "/scripts/actions/terra_rotateUtil.lua"
local queryRange = 100
local keepTargetInRange = 500
local targetPos
local targetId = nil
local ownerId = 0
local approachSpeed = 1
local randomsoundtimer = 0
local maxSpeed = 75
local phase = 0
local phasetimer = -100
local life = 0
local beamAngle = 0
local beamActive = false
-- Engine callback - called on initialization of entity
function init()
  self.shouldDie = false
  ownerId = config.getParameter("ownerId", entity.id())
  self.targets = {}
  targetPos = mcontroller.position()
  self.outOfSight = {}
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
  
  monster.setAggressive(true)

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
  
  monster.setDamageBar("none")
end

function stopMusic()
    return
end
function update(dt)
    life = life + 1
    if life == 2 then
        animator.playSound("spawn")
    end
    randomsoundtimer = randomsoundtimer + 1
    if randomsoundtimer > 240 then
        animator.playSound("random")
        randomsoundtimer = 0
    end
    if world.entityExists(ownerId) then
        self.shouldDie = world.entityHealth(ownerId)[1] <= 0
    else
        self.shouldDie = true
    end
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  monster.setDamageOnTouch(true)
  
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
    local newTargets = world.entityQuery(mcontroller.position(), queryRange, {includedTypes = {"player","npc", "monster"}})
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
    targetId = self.targets[1]
    if targetId == nil then break end

    local newtargetId = targetId
    if not world.entityExists(newtargetId)
       or world.magnitude(world.entityPosition(newtargetId), mcontroller.position()) > keepTargetInRange then
      table.remove(self.targets, 1)
      targetId = nil
    end
    if not targetId or not entity.isValidTarget(newtargetId) then
        table.remove(self.targets, 1)
        targetId = nil
    end

    if not targetId then
      self.outOfSight[newtargetId] = nil
    end
  until #self.targets <= 0 or targetId
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
      local diff = {0, 0}
      for i,v in next, ds.poly do
          if i < #ds.poly then
            diff = vec2.add(diff, vec2.sub(v, ds.poly[i + 1]))
          end
      end
      if vec2.mag(diff) > 0 then
          table.insert(partSources, ds)
      end
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
function updateBeam()
    local beamSource = vec2.add(mcontroller.position(), animator.partPoint("beam", "beamSource"))
    local limit = vec2.add(beamSource, vec2.rotate({100, 0}, beamAngle))
    local dis = world.magnitude(beamSource, world.entityPosition(targetId))
    local beamEnd = world.lineCollision(vec2.add(beamSource, vec2.withAngle(beamAngle, dis)), limit) or limit
    world.debugLine(vec2.add(beamSource, vec2.withAngle(beamAngle, dis)), limit, "blue")
    local beamLength = world.magnitude(vec2.add(mcontroller.position(), animator.partPoint("beam", "beamSource")), beamEnd)
    animator.scaleTransformationGroup("beam", {beamLength + 4.5, 1})
    animator.rotateTransformationGroup("beam", beamAngle)
end
local phaseStartPos
local spheres = {}
function move()
    local decel = 0.95
    local pupilDis = 0
    local pupilDir = 0
    local pupilScale = 1
    if targetId ~= nil then
        local attackTargetPos = world.entityPosition(targetId)
        world.debugLine(mcontroller.position(), world.entityPosition(targetId), "yellow")
        phasetimer = phasetimer + 1
        if phasetimer > 0 then
            decel = 0.8
            approachSpeed = 0
            if phase == 0 then
                pupilScale = 0.75
                pupilDis = 1.5
                pupilDir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
                local toTarget = vec2.withAngle(pupilDir, 240)
                if phasetimer == 30 then
                    animator.playSound("shoot")
                    spawnLeveled.spawnProjectile("moonlordphantasmalbolt", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                elseif phasetimer == 40 then
                    spawnLeveled.spawnProjectile("moonlordphantasmalbolt", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                end
                if phasetimer > 50 then
                    phase = 1
                    phasetimer = -60
                end
            elseif phase == 1 then
                if phasetimer <= 100 then
                    local nextBeamAngle = beamAngle + (math.pi / 3) * 2
                    if phasetimer % 15 > 7 then
                        pupilDis = 1.5
                        pupilDir = nextBeamAngle
                    end
                    if phasetimer % 15 == 0 then
                        beamAngle = beamAngle + (math.pi / 3) * 2
                        table.insert(spheres, spawnLeveled.spawnProjectile("moonlordphantasmalsphere", mcontroller.position(), entity.id(), {0, 0}, false, {level = monster.level(), power=16, targetOffset=vec2.withAngle(beamAngle, 5)}))
                    end
                    if phasetimer == 46 then
                        beamAngle = beamAngle + (math.pi / 3)
                    end
                elseif phasetimer == 120 then
                    beamAngle = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
                elseif phasetimer > 120 then
                    local dirOffset = math.pi / 2
                    pupilDis = 1.5
                    pupilDir = beamAngle
                    if phasetimer < 140 then
                        decel=0.5
                        approachSpeed = 10
                        maxSpeed = 30
                        if phasetimer == 121 then
                            targetPos = vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, -5))
                            for k,v in next, spheres do
                                world.sendEntityMessage(v, "offset", vec2.withAngle(pupilDir, -5))
                            end
                        end
                        local diff = rotateUtil.getRelativeAngle(pupilDir + math.pi, mcontroller.rotation() - dirOffset)
                        mcontroller.setRotation(rotateUtil.slowRotate(mcontroller.rotation() - dirOffset, diff, 0.25) + dirOffset)
                    end
                    if phasetimer > 140 then
                        for k,v in next, spheres do
                            world.sendEntityMessage(v, "launch", pupilDir)
                        end
                        decel=0.98
                        maxSpeed = 90
                        approachSpeed = 90
                        targetPos = vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, 100))
                        spheres = {}
                        local diff = rotateUtil.getRelativeAngle(0, mcontroller.rotation())
                        mcontroller.setRotation(rotateUtil.slowRotate(mcontroller.rotation(), diff, 0.25))
                        if phasetimer > 180 then
                            phase = 2
                            phasetimer = -100
                        end
                    end
                end
            elseif phase == 2 then
                pupilScale = 0.75
                pupilDis = 1.5
                --approachSpeed = 6
                beamAngle = beamAngle + (math.pi * 2 / 60)
                pupilDir = beamAngle
                if phasetimer % 10 == 0 then
                    local toTarget = vec2.withAngle(pupilDir, 60)
                    spawnLeveled.spawnProjectile("moonlordphantasmaleye", vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, pupilDis)), entity.id(), toTarget, false, {level = monster.level(), power=10})
                end
                if phasetimer > 80 then
                    phase = 3
                    phasetimer = -100
                end
            elseif phase == 3 then
                pupilScale = 0.75
                if phasetimer == 120 then
                    local targetDir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
                    beamAngle = targetDir - math.pi / 3
                    animator.playSound("laser")
                elseif phasetimer > 120 and phasetimer < 300 then
                    beamActive = true
                    beamAngle = beamAngle + (math.pi / 270)
                    pupilDis = 2
                    pupilDir = beamAngle
                elseif phasetimer >= 300 then
                    beamActive = false
                    if phasetimer > 310 then
                        phase = 4
                        phasetimer = -100
                    end
                end
            elseif phase == 4 then
                if phasetimer <= 100 then
                    local nextBeamAngle = beamAngle + (math.pi / 3) * 2
                    if phasetimer % 15 > 7 then
                        pupilDis = 1.5
                        pupilDir = nextBeamAngle
                    end
                    if phasetimer % 15 == 0 then
                        beamAngle = beamAngle + (math.pi / 3) * 2
                        table.insert(spheres, spawnLeveled.spawnProjectile("moonlordphantasmalsphere", mcontroller.position(), entity.id(), {0, 0}, false, {level = monster.level(), power=16, targetOffset=vec2.withAngle(beamAngle, 5)}))
                    end
                    if phasetimer == 46 then
                        beamAngle = beamAngle + (math.pi / 3)
                    end
                elseif phasetimer == 120 then
                    beamAngle = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
                elseif phasetimer > 120 then
                    local dirOffset = math.pi / 2
                    pupilDis = 1.5
                    pupilDir = beamAngle
                    if phasetimer < 140 then
                        decel=0.5
                        approachSpeed = 10
                        maxSpeed = 30
                        if phasetimer == 121 then
                            targetPos = vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, -5))
                            for k,v in next, spheres do
                                world.sendEntityMessage(v, "offset", vec2.withAngle(pupilDir, -5))
                            end
                        end
                        local diff = rotateUtil.getRelativeAngle(pupilDir + math.pi, mcontroller.rotation() - dirOffset)
                        mcontroller.setRotation(rotateUtil.slowRotate(mcontroller.rotation() - dirOffset, diff, 0.25) + dirOffset)
                    end
                    if phasetimer > 140 then
                        for k,v in next, spheres do
                            world.sendEntityMessage(v, "launch", pupilDir)
                        end
                        if #spheres > 0 then
                            animator.playSound("attack")
                        end
                        decel=0.98
                        maxSpeed = 90
                        approachSpeed = 90
                        targetPos = vec2.add(mcontroller.position(), vec2.withAngle(pupilDir, 100))
                        spheres = {}
                        local diff = rotateUtil.getRelativeAngle(0, mcontroller.rotation())
                        mcontroller.setRotation(rotateUtil.slowRotate(mcontroller.rotation(), diff, 0.25))
                        if phasetimer > 180 then
                            phase = 0
                            phasetimer = -100
                        end
                    end
                end
            end
        else
            pupilDis = 1.5
            pupilDir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
            beamAngle = pupilDir
            decel = 0.97
            maxSpeed = 75
            approachSpeed = 4
            targetPos = vec2.add(attackTargetPos, {0, 10})
            beamActive = false
            phaseStartPos = mcontroller.position()
            mcontroller.setRotation(0)
        end
    else
        beamActive = false
        phase = 0
        phasetimer = -100
        targetPos = {mcontroller.xPosition(), 0}
    end
    mcontroller.controlFace(1)
    world.debugLine(mcontroller.position(), targetPos, "red")
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    local toTarget = vec2.withAngle(dir, approachSpeed)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > maxSpeed then
        local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
        local approach = {math.cos(angle), math.sin(angle)}
        local new = vec2.mul(approach, maxSpeed)
        mcontroller.setVelocity(new)
    end
    
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
    animator.resetTransformationGroup("pupil")
    animator.resetTransformationGroup("pupilscale")
    animator.resetTransformationGroup("beam")
    animator.scaleTransformationGroup("pupilscale", pupilScale)
    animator.translateTransformationGroup("pupil", vec2.withAngle(pupilDir, pupilDis))
    if beamActive then
        updateBeam()
    else
        animator.scaleTransformationGroup("beam", {0, 0})
        animator.rotateTransformationGroup("beam", beamAngle)
    end
    setDamageSources()
end
