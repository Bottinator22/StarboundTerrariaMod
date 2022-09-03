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
function table.find(org, findValue)
    for key,value in pairs(org) do
        if value == findValue then
            return key
        end
    end
    return nil
end
local shadowAttack = {
          atype= "projectile",
          etype= "cultistshadowfireball",
          power= 12,
          count= 1,
          inaccuracy= math.pi * 0.1
         }
local shouldDie
local targetId
local casting
local attackChainCount = 0
local attackChainDelay = 0
local lastAnim = "idle"
local queryRange
local ownerId
local ritualId = -1
local ritualOffset = {0, 0}
local offset = {0, 0}
local decoys = {}
local keepTargetInRange
local targets
local targetPos
local outOfSight
local phase
local phaseTime
local hasAttacked
local approachSpeed
local collisionPoly
local damageTaken
local forceRegions
local damageSources
local life = 0
function doAttack(attack)
    if attackChainCount <= 0 then
        attackChainCount = attack.chain
        if not attack.chain then
            attackChainCount = 1
        end
    end
    local targetPos = world.entityPosition(targetId)
    local origdir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    local count = 1
    if attack.count then
        count = attack.count
    end
    for i=1,count do
        local dir = origdir
        if attack.inaccuracy then
            dir = dir + (math.random() * 2 - 1) * attack.inaccuracy
        end
        local approach = {math.cos(dir), math.sin(dir)}
        if attack.atype == "projectile" then
            projectileId = spawnLeveled.spawnProjectile(attack.etype, mcontroller.position(), entity.id(), approach, false, {level=monster.level(), power=attack.power})
        elseif attack.atype == "monster" then
            projectileId = world.spawnMonster(attack.etype, mcontroller.position(), {level=monster.level(), ownerId=entity.id(), targetId=targetId, direction=vec2.mul(approach, attack.speed)})
        end
        if not attack.trackProjectile then
            projectileId = entity.id()
        end
    end
    if attack.soundOnlyFirst then
        if attackChainCount == attack.chain then
            animator.playSound(attack.sound)
        end
    else
        if attack.sound then
            animator.playSound(attack.sound)
        end
    end
    if attackChainCount > 0 then
        attackChainCount = attackChainCount - 1
        attackChainDelay = attack.delay
        if not attack.delay then
            attackChainDelay = 0
        end
    end
end
-- Engine callback - called on initialization of entity
function init()
  shouldDie = true
  targetId = nil
  queryRange = 100
  keepTargetInRange = 250
  targets = {}
  targetPos = mcontroller.position()
  outOfSight = {}
  ownerId = config.getParameter("ownerId", -1)
  casting = "fire"
  phase = "init" -- init, initsucc, initstartflying, initfloat, initlaugh, default, cast, ritual, laugh
  phaseTime = 0
  self.notifications = {}
  approachSpeed = 1
  storage.spawnTime = world.time()
  if storage.spawnPosition == nil or config.getParameter("wasRelocated", false) then
    local position = mcontroller.position()
    local groundSpawnPosition
    if mcontroller.baseParameters().gravityEnabled then
      groundSpawnPosition = findGroundPosition(position, -20, 3)
    end
    storage.spawnPosition = groundSpawnPosition or position
  end


  collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)

  animator.setGlobalTag("flipX", "")

  capturable.init()
  
  monster.setAggressive(true)

  -- Listen to damage taken
  damageTaken = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.healthLost > 0 then
        damaged = true
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
      shouldDie = true
      status.addEphemeralEffect("monsterdespawn")
    end)
  message.setHandler("setTarget", function (_, _, target)
                     targetId = target
                     end)
  message.setHandler("cast", function ()
                     doAttack(shadowAttack)
                     phase = "cast"
                     phaseTime = 0
                     hasAttacked = true
                     end)
    message.setHandler("phase", function (_, _, newphase)
                     phase = newphase
                      phaseTime = 0
                      hasAttacked = false
                      end)
    message.setHandler("ritual", function (_, _, ritual, offset)
                       ritualId = ritual
                      ritualOffset = offset
                       end)
        message.setHandler("offset", function (_, _, newoffset)
                      offset = newoffset
                       end)
    message.setHandler("kill", function ()
                       ownerId = -1
                        end)
  forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  damageSources = ControlMap:new(config.getParameter("damageSources", {}))

  --monster.setDamageBar("Special")

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  mcontroller.controlFace(1)
  
end

function update(dt)
  life = life + 1
  if life == 10 then
      animator.playSound("spawn")
  end
    monster.setAggressive(true)
  capturable.update(dt)
  damageTaken:update()

  if status.resourcePositive("stunned") then
    monster.setDamageOnTouch(false)
    return
  else
    monster.setDamageOnTouch(true)
  end
  if #targets == 0 then
    local newTargets = world.entityQuery(mcontroller.position(), queryRange, {includedTypes = {"player","npc", "monster"}})
    table.sort(newTargets, function(a, b)
      return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
    end)
    for _,entityId in pairs(newTargets) do
      if true then
        table.insert(targets, entityId)
      end
    end
  end
repeat
    targetId = targets[1]
    if targetId == nil then break end

    local newtargetId = targetId
    if not world.entityExists(newtargetId)
       or world.magnitude(world.entityPosition(newtargetId), mcontroller.position()) > keepTargetInRange then
      table.remove(targets, 1)
      targetId = nil
    end
    if not targetId or not entity.isValidTarget(newtargetId) then
        table.remove(targets, 1)
        targetId = nil
    end

    if not targetId then
      outOfSight[newtargetId] = nil
    end
  until #targets <= 0 or targetId
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
end

function shouldDie()
  return (shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
    if not capturable.justCaptured then
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

  local damageSources = util.mergeLists(partSources, damageSources:values())
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
  local regions = util.map(forceRegions:values(), function(region)
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
function getAttack()
    local attack = attackCycle[currentAttack]
    if attackChainCount > 0 then
        return casting
    elseif status.resourcePercentage("health") < 0.5 then
        if math.random() < 0.1 then
            return "star"
        end
    end
    return attack
end
function updateAnim()
    local anim = phase
    local targetPos = world.entityPosition(targetId)
    local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
    local angleDiff = rotateUtil.getRelativeAngle(dir, math.pi * 0.5)
    if phase == "ritual" then
        
    else
        if angleDiff > 0 then
            mcontroller.controlFace(1)
        else
            mcontroller.controlFace(-1)
        end
    end
    if phase == "init" then
        anim = "standing"
    elseif phase == "initsucc" then
        anim = "standingcast"
    elseif phase == "initstartflying" then
        anim = "flywindup"
    elseif phase == "initfloat" or phase == "default" then
        anim = "idle"
    elseif phase == "initlaugh" then
        anim = "laugh"
        if lastAnim ~= "laugh" then
            animator.playSound("laugh")
        end
    elseif phase == "ritual" then
        local targetPos = world.entityPosition(ritualId)
        local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
        local angleDiff = rotateUtil.getRelativeAngle(dir, math.pi * 0.5)
        if angleDiff > 0 then
            mcontroller.controlFace(1)
        else
            mcontroller.controlFace(-1)
        end
        anim = "cast"
        local angle = math.abs(angleDiff)
        if angle < math.pi * 0.4 then
            anim = "castup"
        end
        if angle > math.pi * 0.8 then
            anim = "idle"
        end
    elseif phase == "cast" then
        local angle = math.abs(angleDiff)
        if angle < math.pi * 0.4 then
            anim = "castup"
        end
    end
    lastAnim = anim
    animator.setAnimationState("body", anim)
    animator.setParticleEmitterActive("afterimage", phase == "default")
end
function move()
    if not world.entityExists(ownerId) then
        status.setResourcePercentage("health", 0)
    end
    approachSpeed = 50
    if not targetId or not world.entityExists(targetId) then
        targetPos = {mcontroller.xPosition(), 0}
    else
        updateAnim()
    phaseTime = phaseTime + 1
    if phase == "cast" then
        mcontroller.setPosition(vec2.add(world.entityPosition(ownerId), offset))
        if phaseTime > 100 then
            phase = "default"
            phaseTime = 0
            hasAttacked = false
        end
    elseif phase == "default" then
        mcontroller.setPosition(vec2.add(world.entityPosition(ownerId), offset))
    elseif phase == "ritual" then
        mcontroller.setPosition(vec2.add(world.entityPosition(ritualId), ritualOffset))
    end
    if phase == "ritual" then
        if status.resourcePercentage("health") < 1 then
            status.setResourcePercentage("health", 0)
            world.sendEntityMessage(ownerId, "decoydie")
        end
    else
        status.setResourcePercentage("health", 1)
        status.addEphemeralEffect("invulnerable", 0.25)
    end
    targetPos = mcontroller.position()
    end
    if world.magnitude(mcontroller.position(), targetPos) < 1 then
        mcontroller.setPosition(targetPos)
        mcontroller.setVelocity({0, 0})
        moving = false
    else
        local dir = vec2.angle(world.distance(targetPos, mcontroller.position()))
        local approach = {math.cos(dir), math.sin(dir)}
        local toTarget = vec2.mul(approach,approachSpeed)
        mcontroller.setVelocity(toTarget)
        moving = true
    end
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
end
