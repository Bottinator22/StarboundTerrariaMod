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
local attacks = {
    fire={
          atype= "projectile",
          etype= "cultistfireball",
          power= 12,
          count= 3,
          inaccuracy= math.pi * 0.2
         },
    ice={
         atype= "monster",
         etype= "cultisticemist",
         speed= 10
         },
    lightning={
        atype= "monster",
        etype= "cultistlightning",
        speed= 1,
        trackProjectile=true,
        sound= "castlightning",
               },
    star={
        atype= "monster",
        etype= "cultistancientlight",
        speed= 15,
        count= 5,
        inaccuracy= math.pi * 0.3,
        chain= 2,
        delay= 35
         }
}
local decoyFormation = {
    {6, -3},
    {-6, -3},
    {3, -1.5},
    {-3, -1.5},
    {9, -4.5},
    {-9, -4.5}
}
local attackCycle = {"fire", "ice", "lightning"}
local attackCycles = 0
local currentAttack = 1
local projectileId = -1
local ritualStartHealth = 1
local shouldDie
local targetId
local phantdragon
local ritualId
local casting
local attackChainCount = 0
local attackChainDelay = 0
local lastAnim = "idle"
local lastcasted = "fire"
local queryRange
local decoys = {}
local keepTargetInRange
local targets
local targetPos
local outOfSight
local phase
local phaseTime
local approachSpeed
local collisionPoly
local damageTaken
local forceRegions
local damageSources
local moving = true
local life = 0
local hasAttacked = false
local ritualFormation = {}
local initPhases = {
    init={
          time=120,
          next= "initsucc"
          },
    initsucc={
              time=90,
              next="initstartflying"
              },
    initstartflying={
              time=10,
              next="initfloat"
                     },
    initfloat={
              time=60,
              next="initlaugh"
              },
    initlaugh={
              time=60,
              next="default"
              }
    }
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
    if attackChainCount == 0 then
        currentAttack = currentAttack + 1
        if currentAttack > 3 then
            currentAttack = 1
        end
        attackCycles = attackCycles + 1
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
    stopMusic()
    end)
  message.setHandler("decoydie", function ()
                    phaseTime = 1001
                     end)
  forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  damageSources = ControlMap:new(config.getParameter("damageSources", {}))

  monster.setDamageBar("Special")

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  mcontroller.controlFace(1)
  
end

function stopMusic()
end
function update(dt)
  life = life + 1
  if life == 10 then
      animator.playSound("spawn")
  end
  if status.resourcePercentage("health") == 0 then
        stopMusic()
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
  -- player music
  local players = world.playerQuery(mcontroller.position(), queryRange * 2)
  for _,entityId in pairs(players) do
      local pos = world.entityPosition(entityId)
      local dis = world.magnitude(pos, mcontroller.position())
      if dis < queryRange then
          world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=queryRange,priority=monster.level() + 10})
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
end

function shouldDie()
  return (shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
    if not capturable.justCaptured then
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
    elseif phase == "ritual" then
        anim = "idle"
        if lastAnim ~= "ritual" then
            animator.playSound("misc")
        end
    elseif phase == "cast" then
        local angle = math.abs(angleDiff)
        if angle < math.pi * 0.4 then
            anim = "castup"
        end
    end
    lastAnim = anim
    animator.setAnimationState("body", anim)
    animator.setParticleEmitterActive("afterimage", phase == "initfloat" or phase == "default")
end
function setDecoyPhases(phase)
    for k, v in next, decoys do
        world.sendEntityMessage(v, "phase", phase)
    end
end
function decoyAttack()
    for k, v in next, decoys do
        world.sendEntityMessage(v, "setTarget", targetId)
        world.sendEntityMessage(v, "cast")
    end
end
function decoyMove()
    for k, v in next, decoys do
        world.sendEntityMessage(v, "setTarget", targetId)
        world.sendEntityMessage(v, "cast")
    end
end
function updateDecoyFormations()
    for k,v in next,decoys do
        world.sendEntityMessage(v, "offset", decoyFormation[k])
    end
end
function cleanupDecoys()
    local newdecoys = {}
    for k, v in next, decoys do
        if world.entityExists(v) then
            table.insert(newdecoys, v)
        end
    end
    decoys = newdecoys
end
function move()
    cleanupDecoys()
    approachSpeed = 50
    if not targetId or not world.entityExists(targetId) then
        targetPos = {mcontroller.xPosition(), 0}
    else
    updateAnim()
    phaseTime = phaseTime + 1
    if initPhases[phase] then
        if phase == "initfloat" then
            targetPos = vec2.add(mcontroller.position(), {0, 5})
            approachSpeed = 5
        else
            targetPos = mcontroller.position()
        end
        local initPhase = initPhases[phase]
        if phaseTime > initPhase.time then
            phase = initPhase.next
            phaseTime = 0
        end
    elseif phase == "cast" then
        attackChainDelay = attackChainDelay - 1
        casting = getAttack()
        if attackChainDelay <= 0 and attackChainCount > 0 then
            lastcasted = casting
            doAttack(attacks[casting])
        elseif not hasAttacked then
            lastcasted = casting
            doAttack(attacks[casting])
            hasAttacked = true
            decoyAttack()
        end
        if attackChainCount > 0 then
            phaseTime = 0
        end
        if phaseTime > 100 and lastcasted ~= "lightning" then
            phase = "default"
            hasAttacked = false
            phaseTime = 0
            setDecoyPhases(phase)
        elseif phaseTime > 200 and lastcasted == "lightning" then
            phase = "default"
            hasAttacked = false
            phaseTime = 0
            setDecoyPhases(phase)
        elseif hasAttacked and not world.entityExists(projectileId) then
            phaseTime = 300
        end
    elseif phase == "default" then
        updateDecoyFormations()
        if not hasAttacked then
            targetPos = vec2.add(world.entityPosition(targetId), {0, 10})
            hasAttacked = true
        end
        if phaseTime > 5 then
            hasAttacked = false
            if attackCycles >= 5 then
                phase = "ritual"
                status.addEphemeralEffect("invulnerable", 1)
                ritualId = world.spawnMonster("cultistritual", mcontroller.position(), {level=monster.level(), ownerId=entity.id()})
                for i = 1,2 do
                    if #decoys < 6 then
                        table.insert(decoys, world.spawnMonster("cultistdecoy", mcontroller.position(), {level=monster.level(), ownerId=entity.id()}))
                    end
                end
                local formation = {}
                local dis = 10
                local num = #decoys + 1
                local angle = math.pi * 2 / num
                local start = math.floor(math.random() * num)
                local curangle = angle * start
                for i=0,num do
                    table.insert(formation, vec2.mul({math.cos(curangle), math.sin(curangle)}, dis))
                    curangle = curangle + angle
                end
                for k, v in next, decoys do
                    world.sendEntityMessage(v, "ritual", ritualId, formation[k + 1])
                end
                ritualStartHealth = status.resourcePercentage("health")
                ritualFormation = formation
                attackCycles = 0
            else
                phase = "cast"
            end
            phaseTime = 0
            setDecoyPhases(phase)
        end
        if moving then
            phaseTime = 0
        end
    elseif phase == "laugh" then
        if phaseTime > 0 then
            phase = "default"
            phaseTime = 0
            hasAttacked = false
            setDecoyPhases(phase)
        end
    elseif phase == "ritual" then
        mcontroller.setPosition(vec2.add(world.entityPosition(ritualId), ritualFormation[1]))
        targetPos = mcontroller.position()
        if status.resourcePercentage("health") < ritualStartHealth then
            phaseTime = 1001
            hasAttacked = true
        end
        if phaseTime > 750 then
            if not hasAttacked then
                local doPhantasm = not phantdragon
                if not doPhantasm then
                    doPhantasm = not world.entityExists(phantdragon)
                end
                if doPhantasm then
                    phantdragon = world.spawnMonster("phantasmdragonhead", world.entityPosition(ritualId), {level=monster.level()})
                else
                    world.spawnMonster("ancientvision", world.entityPosition(ritualId), {level=monster.level()})
                end
                animator.playSound("summon")
                phase = "laugh"
            else
                for k, v in next, decoys do
                    world.sendEntityMessage(v, "kill")
                end
                decoys = {}
                phase = "default"
            end
            phaseTime = -100
            world.sendEntityMessage(ritualId, "kill")
            setDecoyPhases(phase)
        end
    else
        hasAttacked = false
        phase = "default"
        phaseTime = 0
    end
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
