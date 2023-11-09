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

-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    fireTime = math.random(0, 250)
    ownerId = config.getParameter("ownerId")
  targetId = nil
  targetPos = mcontroller.position()
  queryRange = 100
  keepTargetInRange = 250
  targets = {}
    outOfSight = {}
targetCheckTPS = 3
targetCheckTime = 0
orbitDis = math.random() * 10 + 10
orbitDir = 0
orbitDirDir = (math.random() - 0.5) * 0.1
if orbitDirDir < 0.025 and orbitDirDir > -0.025 then
    if orbitDirDir > 0 then
        orbitDirDir = 0.03
    else
        orbitDirDir = -0.03
    end
end
maxSpeed = 50
monster.setAggressive(true)

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
  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
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
  damageTaken = damageListener("damageTaken", function(notifications)
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
  
  mcontroller.controlFace(1)
  monster.setDamageOnTouch(true)
end
function targeting()
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
    if not world.entityExists(testTargetId)
       or world.magnitude(world.entityPosition(testTargetId), mcontroller.position()) > keepTargetInRange then
      table.remove(targets, 1)
      testTargetId = nil
    end
    if not testTargetId or not entity.isValidTarget(testTargetId) then
        table.remove(targets, 1)
        testTargetId = nil
    end

    if not testTargetId then
      outOfSight[targetId] = nil
    end
    targetId = testTargetId
  until #targets <= 0 or targetId
    targetCheckTime = 0
  end
end
function firing()
    if not targetId then
        --followMove()
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
        if not status.resourcePositive("stunned") then
            if not world.lineTileCollision(mcontroller.position(), world.entityPosition(targetId), {"Block", "Dynamic", "Slippery"}) then -- trying to shoot target will fail (projectile hits block), so don't shoot
                animator.playSound("fire")
                local dir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
                local approach = {math.cos(dir), math.sin(dir)}
                local toTarget = vec2.mul(approach,1)
                spawnLeveled.spawnProjectile("pinklaser", mcontroller.position(), entity.id(), toTarget, false, {level=monster.level(),power=8})
                fireTime = 250
            else
                fireTime = 10
            end
        else
            fireTime = 250
        end
    end
    move()
end
function isProbe()
  return true
end
function update(dt)
  
  damageTaken:update()
  
  targeting()
  firing()
  animator.setLightActive("glow", not world.pointTileCollision({math.floor(mcontroller.xPosition()+0.5), math.floor(mcontroller.yPosition()+0.5)}, {"Block"}))
end
function move()
    orbitDir = orbitDir + orbitDirDir
    local directTargetPos = world.entityPosition(targetId)
    if world.magnitude(mcontroller.position(), directTargetPos) > orbitDis + 5 then
        orbitDir = vec2.angle(world.distance(mcontroller.position(), directTargetPos))
    end
    targetPos = vec2.add(vec2.mul({math.cos(orbitDir), math.sin(orbitDir)},orbitDis), directTargetPos)
    
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), 0.99), vec2.mul({math.cos(dir), math.sin(dir)},0.75)))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > maxSpeed then
      local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
      mcontroller.setVelocity(vec2.mul({math.cos(angle), math.sin(angle)}, maxSpeed))
    end
    local myDir = mcontroller.rotation()
    mcontroller.setRotation(rotateUtil.slowRotate(myDir, rotateUtil.getRelativeAngle(vec2.angle(world.distance(directTargetPos, mcontroller.position())), myDir), 0.25))
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
end
function followMove()
    if not ownerId then
        return
    end
    if not world.entityExists(ownerId) then
        return
    end
    orbitDir = orbitDir + orbitDirDir
    local directTargetPos = world.entityPosition(ownerId)
    if world.magnitude(mcontroller.position(), directTargetPos) > 10 then
        orbitDir = vec2.angle(world.distance(mcontroller.position(), directTargetPos))
    end
    targetPos = vec2.add(vec2.mul({math.cos(orbitDir), math.sin(orbitDir)},5), directTargetPos)
    
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), 0.99), vec2.mul({math.cos(dir), math.sin(dir)},0.75)))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > maxSpeed then
      local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
      mcontroller.setVelocity(vec2.mul({math.cos(angle), math.sin(angle)}, maxSpeed))
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
