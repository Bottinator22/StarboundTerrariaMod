require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/drops.lua"
require "/scripts/status.lua"
require "/scripts/tenant.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/actions/terra_spawnLeveled.lua"

local probeHealth
local fireTime
local ownerId
local life
local initialized
local headId
local targetId
local queryRange
local keepTargetInRange
local targets
local outOfSight
local size
local probe
local releasingProbe
local probeId
local childId
local targetCheckTPS
local targetCheckTime
local lastHealth
local segmentSize
local maxBend
local isFirst = false
local damageTimer = 0
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    fireTime = math.random(0, 250)
ownerId = 1
life = 0
initialized = false
headId = 0
  targetId = nil
  queryRange = 100
  keepTargetInRange = 250
  targets = {}
    outOfSight = {}
size = 0
probe = true
releasingProbe = false
probeId = 0
childId = 0
targetCheckTPS = 80
targetCheckTime = config.getParameter("segmentsLeft") % targetCheckTPS
lastHealth = 0
monster.setAggressive(true)
segmentSize = config.getParameter("segmentSize") * -1
maxBend = config.getParameter("maxBend", 180) * math.pi / 180
lastHealth = status.resourcePercentage("health")
setHealth(config.getParameter("ownerHealth"))

    message.setHandler("healthOwner", function(_,_,health)
        setHealth(health)
        sendHealthOwner(health)
  end)
    message.setHandler("healthChild", function(_,_,health)
        setHealth(health)
        sendHealthChild(health)
  end)
  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
        setVariables(config.getParameter("ownerId"), config.getParameter("segmentsLeft"), config.getParameter("headId"))
  end)
    message.setHandler("update", function(_, _, angle)
        if not initialized then
            return
        end
        followOwner(angle)
        if world.entityExists(childId) then
            world.sendEntityMessage(childId, "update", mcontroller.rotation())
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

  --self.behavior = behavior.behavior(config.getParameter("behavior"), sb.jsonMerge(config.getParameter("behaviorConfig", {}), skillBehaviorConfig()), _ENV)
  --self.board = self.behavior:blackboard()
  --self.board:setPosition("spawn", storage.spawnPosition)

  self.collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
      if config.getParameter("segmentsLeft") % 5 == 0 then
        monster.setDeathSound("deathPuff")
      end
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)
  --self.behaviorTickRate = config.getParameter("behaviorUpdateDelta", 2)
  --self.behaviorTick = math.random(1, self.behaviorTickRate)

  animator.setGlobalTag("flipX", "")
  --self.board:setNumber("facingDirection", mcontroller.facingDirection())

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
    end)

  local deathBehavior = config.getParameter("deathBehavior")
  if deathBehavior then
    --self.deathBehavior = behavior.behavior(deathBehavior, config.getParameter("behaviorConfig", {}), _ENV, self.behavior:blackboard())
  end

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false

  if config.getParameter("damageBar") then
    monster.setDamageBar(config.getParameter("damageBar"));
  end

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", {})
  
  mcontroller.controlFace(1)
end
function collectSegments(segmentposes)
    table.insert(segmentposes, mcontroller.position())
    world.callScriptedEntity(childId, "collectSegments", segmentposes)
end
function updateMove(angle)
    if not initialized then
        return
    end
    followOwner(angle)
    if world.entityExists(childId) then
        world.callScriptedEntity(childId, "updateMove", mcontroller.rotation())
    end
end
function targeting()
    targetCheckTime = targetCheckTime + 1  
    if targetCheckTime >= targetCheckTPS - 1 then
        if releasingProbe then
            if probe then
                if status.resourcePercentage("health") > 0.01 then
                    trueReleaseProbe()
                    animator.setAnimationState("body", "probeless")
                end
            end
        end
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
    if testTargetId then 
        if world.lineTileCollision(mcontroller.position(), world.entityPosition(testTargetId), {"Block", "Dynamic", "Slippery"}) then -- trying to shoot target will fail (projectile hits block), so target is invalid
            table.remove(targets, 1)
            testTargetId = nil
        end
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
        if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Dynamic", "Slippery"}) then
            animator.playSound("fire")
            local dir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
            local approach = {math.cos(dir), math.sin(dir)}
            local toTarget = vec2.mul(approach,1)
            spawnLeveled.spawnProjectile("redlaser", mcontroller.position(), entity.id(), toTarget, false, {level=monster.level(),power=10})
        end
        end
        fireTime = 250
    end
end
function update(dt)
     life = life + 1
     if life > 15 then
         if life < 30 then
            monster.setDamageOnTouch(true)
         end
         if not world.entityExists(ownerId) then
             status.setResourcePercentage("health", 0) 
         end
     end
  local damageTaken, nextStep = status.damageTakenSince(damageTimer)
  for k,v in  next, damageTaken do
    if status.resourcePercentage("health") ~= lastHealth then
        sendHealthChild(status.resourcePercentage("health"))
        lastHealth = status.resourcePercentage("health")
            
    end
    if probe then
        if not releasingProbe then
            if math.random() > 0.75 then
                releasingProbe = true
            end
        end
    end
  end
  damageTimer = nextStep
  if probe then
    targeting()
    firing()
  end
  if lastHealth ~= status.resourcePercentage("health") then
      lastHealth = status.resourcePercentage("health")
      sendHealthOwner(lastHealth)
      sendHealthChild(lastHealth)
  end
  if childId then
    if not world.entityExists(childId) then
        if status.resourcePercentage("health") > 0 then
            spawnSegment(size, headId)
        end
    end
  end
  animator.setLightActive("glow", probe and not world.pointTileCollision({math.floor(mcontroller.xPosition()+0.5), math.floor(mcontroller.yPosition()+0.5)}, {"Block"}))
end

function skillBehaviorConfig()
  local skills = config.getParameter("skills", {})
  local skillConfig = {}
    if probe then
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
end

function shouldDie()
    
    return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
  sendHealthChild(0)
  sendHealthOwner(0)
  --disabled since body doesn't have drops anymore
  --if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"}) then
  --      if life > 100 then
  --          spawnDrops()
  --      end
  --end
end
function followOwner(ownerDir)
  if world.entityExists(ownerId) then
        local ownerPos = world.entityPosition(ownerId)
        if isFirst then
            local ownerVel = world.entityVelocity(ownerId)
            ownerPos = vec2.add(ownerPos, vec2.mul(ownerVel, script.updateDt()))
        end
        local angle = vec2.angle(world.distance(ownerPos, mcontroller.position()))
        mcontroller.setPosition(vec2.add(ownerPos, vec2.mul({math.cos(angle), math.sin(angle)}, segmentSize)))
        mcontroller.setVelocity({0, 0})
        mcontroller.setRotation(angle)
        animator.resetTransformationGroup("body")
        animator.rotateTransformationGroup("body", angle)
        --world.debugLine(mcontroller.position(), bossPosition, "red")
  else
     if life < 100 then
         mcontroller.setPosition({0, 0})
     end
      status.setResourcePercentage("health", 0) 
  end
end
function setVariables(newownerId, count, newheadId)
    ownerId = newownerId
    headId = newheadId
    if headId == ownerId then
        isFirst = true
    end
    size = count
    initialized = true
    spawnSegment(count, headId)
    status.setStatusProperty("headId", headId)
    message.setHandler("pet.attemptCapture", function(_,_,...)
                        return world.callScriptedEntity(headId, "capturable.attemptCapture", ...)
                         end)
end
function sendHealthOwner(health)
    --world.sendEntityMessage(ownerId, "healthOwner", health)
end
function sendHealthChild(health)
    world.sendEntityMessage(childId, "healthChild", health)
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
function spawnSegment(count, tempHeadId)
    if count > 0 then
    local tempownerId = entity.id()
    local segmentId = world.spawnMonster("wormbossbody",mcontroller.position(), { level = monster.level(),ownerHealth = status.resourcePercentage("health"),ownerId = tempownerId, segmentsLeft = count - 1, headId = tempHeadId})
    childId = segmentId
    world.sendEntityMessage(segmentId, "damageTeam", entity.damageTeam())
  return true, segmentID
    else
    local tempownerId = entity.id()
    local segmentId = world.spawnMonster("wormbosstail",mcontroller.position(), { level = monster.level(),ownerHealth = status.resourcePercentage("health"),ownerId = tempownerId, headId = tempHeadId})
    childId = segmentId
    world.sendEntityMessage(segmentId, "damageTeam", entity.damageTeam())
    return true, segmentID
    end
end
function trueReleaseProbe()
    probe = false
    releasingProbe = false
    probeId = world.spawnMonster("probe", mcontroller.position(), { level = monster.level(), ownerId = entity.id()})
    world.sendEntityMessage(probeId, "damageTeam", entity.damageTeam())
end
