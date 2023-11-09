require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/tenant.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
function spawnSegment(count)
    local tempownerId = entity.id()
--  local stepAngle = (math.pi * 2) / count
--  local offset = vec2.rotate({1,0}, stepAngle * 1)
    local tempLevel = monster.level()
    if ownerId() then
        tempLevel = 5
    end
    local segmentId = world.spawnMonster("terraria_destroyerbody", mcontroller.position(), { level = tempLevel,ownerHealth = status.resourcePercentage("health"),ownerId = tempownerId, segmentsLeft = count - 1, headId = tempownerId})
    world.sendEntityMessage(segmentId, "damageTeam", entity.damageTeam())
    self.childId = segmentId

  return true, segmentID
end
function ownerId()
    if capturable.ownerUuid() then
        local playerIds = world.players()
        table.sort(playerIds, function(a)
      return world.entityUniqueId(a) == capturable.ownerUuid() end)
        return playerIds[1]
    else
        return nil
    end
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
local minSpeed
local maxSpeed
local maxNullSpeed
local loadRange
local digSound
local digSoundMinSpeed
local digSoundSpeedDiv
local digSoundSpeed
local digSoundTimer = 0
-- Engine callback - called on initialization of entity
function init()
  self.pathing = {}
self.childId = 0
self.inGround = true
self.wasInGround = true
self.noControlTimer = 0
self.offScreen = true
self.inGroundTimer = 0
self.life = 0
self.lastHealth = status.resourcePercentage("health")
    minSpeed = config.getParameter("minSpeed", 1) -- enables smoother turning for worms
    maxSpeed = config.getParameter("maxSpeed", 25) -- makes worms more controllable
    maxNullSpeed = config.getParameter("maxNullSpeed", 0.01) -- helps prevent the worm from despawning
    digSound = config.getParameter("digSound")
    digSoundSpeedDiv = config.getParameter("digSoundSpeedDiv", 2)
    digSoundSpeed = config.getParameter("digSoundSpeed", 1)
    digSoundMinSpeed = config.getParameter("digSoundMinSpeed", 5)
  self.shouldDie = true
  self.speed = 0
  self.targetId = nil
  loadRange = 150
  self.musicRange = 200
  self.queryRange = 5000
  self.targets = {}
  self.ignoreBody = 25
  self.outOfSight = {}
  self.notifications = {}
  self.approachSpeed = 2
  self.gravity = -0.25
  self.targetCheckTime = 0
  monster.setAggressive(true)
      message.setHandler("healthOwner", function(_,_,health)
      if self.ignoreBody <= 0 then  
        setHealth(health)
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
      self.queryRange = 0
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

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  spawnSegment(config.getParameter("size"))
  mcontroller.controlFace(1)
end
function takeDamage(damageRequest)
    status.applySelfDamageRequest(damageRequest)
end
function stopMusic()
end
function targeting()
    self.targetCheckTime = self.targetCheckTime + 1
    if self.targetCheckTime > 20 then -- due to the MASSIVE range this is an expensive process, so don't do it too often
        self.targetCheckTime = 0
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
    if not world.entityExists(targetId) then
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
end
end
function update(dt)
  self.ignoreBody = self.ignoreBody - 1
  if status.resourcePercentage("health") == 0 then
        stopMusic()
    end
  capturable.update(dt)
  self.damageTaken:update()

  self.life = self.life + 1
     if self.life > 15 then
         monster.setDamageOnTouch(true)
     end
  
  self.gravity = world.gravity(mcontroller.position()) / -160
  if world.gravity(mcontroller.position()) == 0 then
      self.inGround = true
  else
        self.inGround = world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Platform", "Dynamic", "Slippery"})
    if not self.inGround then
        if world.liquidAt({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}) then
            self.inGround = true
        end
    end
  end
  local mypos = mcontroller.position()
  local roundedpos = {math.floor(mypos[1]+0.5), math.floor(mypos[2]+0.5)}
  local nextpos = vec2.add(mypos, vec2.mul(mcontroller.velocity(), 2))
  local roundednextpos = {math.floor(nextpos[1]+0.5), math.floor(nextpos[2]+0.5)}
  local rect = {world.xwrap(nextpos[1] - loadRange), nextpos[2] - loadRange, world.xwrap(nextpos[1] + loadRange), nextpos[2] + loadRange}
  
  local poly = {
      {world.xwrap(nextpos[1] - loadRange), nextpos[2] + loadRange},
      {world.xwrap(nextpos[1] - loadRange), nextpos[2] - loadRange},
      {world.xwrap(nextpos[1] + loadRange), nextpos[2] - loadRange},
      {world.xwrap(nextpos[1] + loadRange), nextpos[2] + loadRange}
  }
  world.debugPoly(poly, "green")
  world.debugLine(mypos, nextpos, "green")
  world.loadRegion(rect)
  
  if entity.uniqueId() == nil then
      world.setUniqueId(entity.id(), math.floor(math.random() * 1000000))
  end
  world.loadUniqueEntity(entity.uniqueId())
  local targetFindPoly = makeCirclePoly(self.queryRange, mcontroller.xPosition(), mcontroller.yPosition())
  local playerMusicPoly = makeCirclePoly(self.musicRange, mcontroller.xPosition(), mcontroller.yPosition())
  world.debugPoly(targetFindPoly, "red")
  world.debugPoly(playerMusicPoly, "blue")
  if not self.inGround then
      self.inGroundTimer = 0
  end
  if self.lastHealth ~= status.resourcePercentage("health") then
      self.lastHealth = status.resourcePercentage("health")
      sendHealthChild(status.resourcePercentage("health"))
  end
  targeting()
  if not status.resourcePositive("stunned") then
    move()
  else
    --mcontroller.clearControls()
  end
  if self.childId then
    if not world.entityExists(self.childId) then
        if status.resourcePercentage("health") > 0 then
            spawnSegment(config.getParameter("size", 80))
        end
    else
        world.callScriptedEntity(self.childId, "updateMove", mcontroller.rotation())
    end
  end
  self.behaviorTick = self.behaviorTick + 1
  -- player music
  local players = world.playerQuery(mcontroller.position(), self.musicRange)
  for _,entityId in pairs(players) do
        world.sendEntityMessage(entityId, "terraMusic", {id=entity.id(),file=config.getParameter("music"),expireType="entityDistance",entityID=entity.id(),entityDis=self.musicRange,priority=monster.level() + 10})
    end
    if digSound then
        if self.inGround then
            if self.targetId then
                local dis = world.magnitude(mcontroller.position(), world.entityPosition(self.targetId))
                digSoundTimer = digSoundTimer + digSoundSpeed
                if digSoundTimer > digSoundMinSpeed + dis / digSoundSpeedDiv then
                    digSoundTimer = 0
                    animator.playSound("dig")
                end
            end
        end
    end
  animator.setLightActive("glow", not world.pointTileCollision({math.floor(mcontroller.xPosition()+0.5), math.floor(mcontroller.yPosition()+0.5)}, {"Block"}))
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
  local segmentposes = {mcontroller.position()}
  if not ownerId() then
    world.callScriptedEntity(self.childId, "collectSegments", segmentposes)
  end
  sendHealthChild(0)
    if not capturable.justCaptured then
    if self.deathBehavior then
      self.deathBehavior:run(script.updateDt())
    end
    capturable.die()
  end
end
function nearestPosition(positions, nearposition)
  local bestDistance = nil
  local bestPosition = nil
  for _,position in next, positions do
    local distance = world.magnitude(position, nearposition)
    if not bestDistance or distance < bestDistance then
      bestPosition = position
      bestDistance = distance
    end
  end
  return bestPosition
end
function collectSegmentsDone(segmentposes)
    local pos = mcontroller.position()
    if self.targetId then
        pos = world.entityPosition(self.targetId)
    end
    world.spawnTreasure(nearestPosition(segmentposes, pos), "theDestroyer", monster.level())
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
function sendHealthChild(health)
    world.sendEntityMessage(self.childId, "healthChild", health)
    if health == 0 then
        stopMusic()
    end
end
function setHealth(health)
    self.lastHealth = health
    status.setResourcePercentage("health", health)
    if health == 0 then
        stopMusic()
    end
end
function move()
    if world.timeOfDay() < 0.5 and not ownerId() then
        self.targetId = nil
    end
    allowDig = config.getParameter("allowDig", true) -- whether or not the worm AI will continue digging when it hits the ground, before going for another pass
    digMax = config.getParameter("digMax", 15) -- how many ticks the worm can dig for
    enforcePass = config.getParameter("enforcePass", false) -- if the worm passes the target while in ground, it will drift for a bit, before going back towards the target, intended for some flying worms to behave more like they do in Terraria
    enforcePassDis = config.getParameter("enforcePassDis", 3)
    enforcePassTime = config.getParameter("enforcePassTime", 60)
    local leaving = false
    function postMove()
        if world.magnitude(mcontroller.velocity(), {0, 0}) > 0.025 then
            mcontroller.setRotation(vec2.angle(world.distance(mcontroller.velocity(),{0, 0})))
        end
  animator.resetTransformationGroup("body")
  animator.rotateTransformationGroup("body", mcontroller.rotation())
    if config.getParameter("flip") then
      local flip = mcontroller.rotation() > 1.5708 and mcontroller.rotation() < 4.71239  
      local anim = config.getParameter("flip")
      if flip then
          animator.setAnimationState("body", anim)
      else
          animator.setAnimationState("body", "idle")
      end
    end
    local speed = world.magnitude(mcontroller.velocity(), {0, 0})
  if speed > maxSpeed or speed < minSpeed then
      if not leaving then
        local angle = vec2.angle(world.distance(mcontroller.velocity(), {0, 0}))
        local approach = {math.cos(angle), math.sin(angle)}
        local new = vec2.mul(approach, math.max(math.min(speed, maxSpeed), minSpeed))
        mcontroller.setVelocity(new)
      end
  end
    if mcontroller.position()[2] < 10 and not leaving then
      mcontroller.setPosition({mcontroller.position()[1], 10})
      mcontroller.setVelocity({mcontroller.xVelocity(), 0})
  end
end
    if allowDig then
        if self.inGround then
            if not self.wasInGround then
                self.noControlTimer = math.random() * digMax
            end
        end
    end
    if self.lastPosition then
       if world.magnitude(self.lastPosition, mcontroller.position()) > maxSpeed * 4 then -- Either moved too fast (which shouldn't happen due to maxSpeed) or teleported
            --mcontroller.setVelocity({0, 0})
       end
   end
   self.lastPosition = mcontroller.position()
   self.wasInGround = self.inGround
    if self.inGround then
        if self.noControlTimer > 0 then
            self.noControlTimer = self.noControlTimer - 1
            postMove()
            return
        end
    end
    local toTarget = {0, 0}
    if not self.targetId then
      if ownerId() then
            if world.magnitude(world.entityPosition(ownerId()), mcontroller.position()) <= 10 then
                if not self.inGround then
                    mcontroller.setVelocity(vec2.add(mcontroller.velocity(), {0, self.gravity})) -- Force to apply for falling
                else 
                    mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.9))
                end
                postMove()
                return
            end
      else
          
      end
  end
    local targetPosition = nil
    if ownerId() then
        if self.targetId  then
        targetPosition = world.entityPosition(self.targetId)
        if enforcePass then
            if world.magnitude(targetPosition, mcontroller.position()) <= enforcePassDis then
                self.noControlTimer = math.random() * enforcePassTime
            end
        end
        else
        self.targetId = nil
        if world.magnitude(world.entityPosition(ownerId()), mcontroller.position()) > 10 then
        targetPosition = world.entityPosition(ownerId())
        end
        end
    elseif self.targetId then
            targetPosition = world.entityPosition(self.targetId)
            if enforcePass then
                if world.magnitude(targetPosition, mcontroller.position()) <= enforcePassDis then
                    self.noControlTimer = math.random() * enforcePassTime
                end
            end
    else
        targetPosition = {mcontroller.xPosition(), 0}
        leaving = true
    end
    if not world.isVisibleToPlayer({mcontroller.xPosition(),mcontroller.yPosition(),mcontroller.xPosition(),mcontroller.yPosition()}) then
        self.inGround = config.getParameter("treatOffScreenAsGround", true)
        self.offScreen = true
  else
        self.offScreen = false
    end
    if self.inGround then
        if not targetPosition then
            mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.9))
            postMove()
            return
        end
        local targetAngle = vec2.angle(world.distance(targetPosition, mcontroller.position()))
        local approach = {math.cos(targetAngle), math.sin(targetAngle)}
        toTarget = vec2.mul(approach,self.approachSpeed)
        if leaving then
            toTarget = vec2.mul(toTarget, 10)
        end
        mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), 0.99), toTarget))
        if self.offScreen then
            --mcontroller.setVelocity(vec2.mul(toTarget, 25)) 
        end
  else 
      mcontroller.setVelocity(vec2.add(mcontroller.velocity(), {0, self.gravity})) -- Force to apply for falling
  end
  postMove()
end
