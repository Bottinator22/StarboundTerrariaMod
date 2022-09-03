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

local fireTime
local ownerId
local managerId
local life
local initialized
local targetId
local queryRange
local targets
local outOfSight
local size
local childId
local targetCheckTPS
local targetCheckTime
local segmentSize
local maxBend
local approachSpeed = 0
local maxSpeed = 0
local expertMode
local wasInGround = false
local inGround = false
local minSpeed
local maxSpeed
local segmentType = "body"
local digSound
local digSoundMinSpeed
local digSoundSpeedDiv
local digSoundSpeed
local digSoundTimer = 0
local gravity = {0, 0}
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    fireTime = math.random(0, 250)
ownerId = -1
managerId = -1
life = 0
initialized = false
  targetId = nil
  queryRange = 250
  targets = {}
    outOfSight = {}
size = 0
childId = -1
targetCheckTPS = 80
targetCheckTime = math.random() * targetCheckTPS
    approachSpeed = config.getParameter("approachSpeed", 1)
    minSpeed = config.getParameter("minSpeed", 1) -- enables smoother turning for worms
    maxSpeed = config.getParameter("maxSpeed", 25) -- makes worms more controllable
    digSound = config.getParameter("digSound")
    digSoundSpeedDiv = config.getParameter("digSoundSpeedDiv", 2)
    digSoundSpeed = config.getParameter("digSoundSpeed", 1)
    digSoundMinSpeed = config.getParameter("digSoundMinSpeed", 5)
expertMode = config.getParameter("expertMode", false)
monster.setAggressive(true)
segmentSize = config.getParameter("segmentSize") * -1
maxBend = config.getParameter("maxBend", 180) * math.pi / 180
  message.setHandler("child", function(_,_,child, damageTeam)
        childId = child
        monster.setDamageTeam(damageTeam)
        setVariables(config.getParameter("ownerId"),config.getParameter("trueOwnerId"))
  end)
    message.setHandler("update", function(_, _, angle)
        if not initialized then
            return
        end
        if segmentType ~= "head" then
            followOwner(angle)
        end
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
     monster.setDeathSound("deathPuff")
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

  -- Listen to damage taken
  damageTaken = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.healthLost > 0 then
        self.damaged = true
        --self.board:setEntity("damageSource", notification.sourceEntityId)
      end
    end
  end)

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
function updateMove(angle)
    if not initialized then
        return
    end
    if segmentType ~= "head" then
        followOwner(angle)
    end
    if world.entityExists(childId) then
        world.callScriptedEntity(childId, "updateMove", mcontroller.rotation())
    end
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
    if not world.entityExists(testTargetId) then
      table.remove(targets, 1)
      testTargetId = nil
    end
    if not testTargetId or not entity.isValidTarget(testTargetId) then
        table.remove(targets, 1)
        testTargetId = nil
    end
    if testTargetId and segmentType == "body" then 
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
            local dir = vec2.angle(world.distance(world.entityPosition(targetId), mcontroller.position()))
            local approach = {math.cos(dir), math.sin(dir)}
            local toTarget = vec2.mul(approach,1)
            spawnLeveled.spawnProjectile("vilespit", mcontroller.position(), entity.id(), toTarget, false, {level=monster.level(),power=10})
        end
        end
        fireTime = 250
    end
end
function update(dt)
    damageTaken:update()
    if not initialized then
        return
    end
     life = life + 1
     if life > 15 then
         if life < 30 then
            monster.setDamageOnTouch(true)
         end
         if not world.entityExists(ownerId) then
             segmentType = "head"
             status.addEphemeralEffect("eaterbosshead")
             animator.setAnimationState("body", "head")
             if not world.entityExists(childId) then
                 segmentType = "dead"
             end
         elseif not world.entityExists(childId) then
             segmentType = "tail"
             status.addEphemeralEffect("eaterbosstail")
             animator.setAnimationState("body", "tail")
         end
     end

  if expertMode or segmentType == "head" then
    targeting()
    if expertMode and segmentType == "body" then
        --firing()
    end
  end
  if segmentType == "dead" then
      status.setResource("health", 0)
  elseif segmentType == "head" then
      headMove()
  end
end

function skillBehaviorConfig()
  return {}
end

function interact(args)
end

function shouldDie()
    
    return (self.shouldDie and status.resource("health") <= 0) or not world.entityExists(managerId)
end

function die()
  if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"}) then
        if life > 100 then
            spawnDrops()
        end
  end
end
function followOwner(ownerDir)
  if world.entityExists(ownerId) then
        local ownerPos = world.entityPosition(ownerId)
        local newAngle = ownerDir + math.max(math.min(rotateUtil.getRelativeAngle(vec2.angle(world.distance(ownerPos, mcontroller.position())), ownerDir), maxBend), maxBend * -1)
        mcontroller.setPosition(vec2.add(ownerPos, vec2.mul({math.cos(newAngle), math.sin(newAngle)}, segmentSize)))
        mcontroller.setVelocity({0, 0})
        mcontroller.setRotation(newAngle)
        animator.resetTransformationGroup("body")
        animator.rotateTransformationGroup("body", newAngle)
        --world.debugLine(mcontroller.position(), bossPosition, "red")
  end
end
function headMove()
    gravity = world.gravity(mcontroller.position()) / -160
    inGround = world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"})
    if gravity == 0 then
        inGround = true
    end
    if not inGround then
        if world.liquidAt({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}) then
            inGround = true
        end
    end
    if digSound then
        if inGround then
            if targetId then
                local dis = world.magnitude(mcontroller.position(), world.entityPosition(targetId))
                digSoundTimer = digSoundTimer + digSoundSpeed
                if digSoundTimer > digSoundMinSpeed + dis / digSoundSpeedDiv then
                    digSoundTimer = 0
                    animator.playSound("dig")
                end
            end
        end
    end
    allowDig = config.getParameter("allowDig", true) -- whether or not the worm AI will continue digging when it hits the ground, before going for another pass
    digMax = config.getParameter("digMax", 15) -- how many ticks the worm can dig for
    function postMove()
        if world.magnitude(mcontroller.velocity(), {0, 0}) > 0.025 then
            mcontroller.setRotation(vec2.angle(world.distance(mcontroller.velocity(),{0, 0})))
        end
        animator.resetTransformationGroup("body")
        animator.rotateTransformationGroup("body", mcontroller.rotation())
        local speed = world.magnitude(mcontroller.velocity(), {0, 0})
        if speed > maxSpeed or speed < minSpeed then
            local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
            local approach = {math.cos(angle), math.sin(angle)}
            local new = vec2.mul(approach, math.max(math.min(speed, maxSpeed), minSpeed))
            mcontroller.setVelocity(new)
        end
        world.callScriptedEntity(childId, "updateMove", mcontroller.rotation())
    end
    if allowDig then
        if inGround then
            if not wasInGround then
                noControlTimer = math.random() * digMax
            end
        end
    end
    if lastPosition then
       if world.magnitude(lastPosition, mcontroller.position()) > maxSpeed * 4 then -- Either moved too fast (which shouldn't happen due to maxSpeed) or teleported
            --mcontroller.setVelocity({0, 0})
       end
   end
   lastPosition = mcontroller.position()
   wasInGround = inGround
    if inGround then
        if noControlTimer > 0 then
            noControlTimer = noControlTimer - 1
            postMove()
            return
        end
    end
    local toTarget = {0, 0}
    local targetPosition = nil
    local owner = world.callScriptedEntity(managerId, "ownerId")
    if targetId then
            targetPosition = world.entityPosition(targetId)
    elseif owner then
        local dis = world.magnitude(world.entityPosition(owner), mcontroller.position())
        if dis > 10 then
            targetPosition = world.entityPosition(owner)
        end
    else
        targetPosition = {mcontroller.xPosition(), 0}
    end
    if inGround then
        if targetPosition then
            world.debugLine(mcontroller.position(), targetPosition, "red") -- boss -> target red line
        else
            mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.9))
            postMove()
        return
    end
    local targetAngle = vec2.angle(world.distance(targetPosition, mcontroller.position()))
    local approach = {math.cos(targetAngle), math.sin(targetAngle)}
    toTarget = vec2.mul(approach,approachSpeed)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), 0.99), toTarget))
  else 
      mcontroller.setVelocity(vec2.add(mcontroller.velocity(), {0, gravity})) -- Force to apply for falling
  end
  postMove()
end
function setVariables(newownerId, newmanagerId)
    ownerId = newownerId or -1
    managerId = newmanagerId
    initialized = true
      message.setHandler("pet.attemptCapture", function(_,_,...)
                        return world.callScriptedEntity(managerId, "capturable.attemptCapture", ...)
                         end)
end
