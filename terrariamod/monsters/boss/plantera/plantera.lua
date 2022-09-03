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
local tentacles = {}
local expertMode = false
function spawnMinion()
    local mownerId = entity.id()
    local handId = world.spawnMonster("planterahook", mcontroller.position(), { level = self.mLevel, ownerId = mownerId, expertMode=expertMode })
    world.sendEntityMessage(handId, "damageTeam", entity.damageTeam())
    table.insert(self.children, handId)
    table.insert(self.activeChildren, "undefined")
end
function replaceMinion(index)
    local mownerId = entity.id()
    local handId = world.spawnMonster("planterahook", mcontroller.position(), { level = self.mLevel, ownerId = mownerId, expertMode=expertMode })
    world.sendEntityMessage(handId, "damageTeam", entity.damageTeam())
    if self.secondPhase then
        world.sendEntityMessage(handId, "secondPhase", "")
    end
    table.remove(self.children, index)
    table.remove(self.activeChildren, index)
    table.insert(self.children, index, handId)
    table.insert(self.activeChildren, index, "undefined")
end
function spawnTentacle()
    local mownerId = entity.id()
    local tentacleId = world.spawnMonster("planteratentacle", mcontroller.position(), { level = self.mLevel, ownerId = mownerId })
    world.sendEntityMessage(tentacleId, "damageTeam", entity.damageTeam())
    table.insert(tentacles, tentacleId)
end
function replaceTentacle(index)
    local mownerId = entity.id()
    local tentacleId = world.spawnMonster("planteratentacle", mcontroller.position(), { level = self.mLevel, ownerId = mownerId })
    world.sendEntityMessage(tentacleId, "damageTeam", entity.damageTeam())
    table.remove(tentacles, index)
    table.insert(tentacles, index, tentacleId)
end
function table.find(org, findValue)
    for key,value in pairs(org) do
        if value == findValue then
            return key
        end
    end
    return nil
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
local enraged = false
local hookRestrictMode = 2 -- 0 = hard restraint when far from closest hook, 1 = soft restraint (a pull from all hooks), 2 = soft restraint (a pull from only latched hooks)
local replaceTentacleTimer = 0
-- Engine callback - called on initialization of entity
function init()
self.offScreen = true
self.children = {}
self.activeChildren = {}
self.debugLineQueue = {}
self.mLevel = monster.level()
    if ownerId() then
        self.mLevel = 6
    end
  self.shouldDie = true
  self.targetId = nil
  self.queryRange = 100
  self.keepTargetInRange = 150
  self.targets = {}
  self.targetPos = mcontroller.position()
  self.outOfSight = {}
  self.phase = "default" -- default
  self.phaseTime = 0
  self.summonTime = 0
  self.chargeDelay = 0
  self.secondPhase = false
  self.secondPhaseTrig = false
  self.maxSpeed = 5
  self.speen = 0
  self.baseTurnSpeed = 0.3
  self.notifications = {}
  self.approachSpeed = 0.2
  self.targetPredictMultiplier = 1 -- how many ticks of player horizontal movement to predict
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
  message.setHandler("hookupdate", function (_,_,childid,status)
                     local index = table.find(self.children,childid)
                    if not index then
                        sb.logError("Unknown Plantera hook "..childid)
                        return
                    end
                    self.activeChildren[index] = status
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
  spawnMinion()
  spawnMinion()
  spawnMinion()
  --spawnMinion()
end

function stopMusic()
end
function update(dt)
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  monster.setAggressive(true)
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
    local newTargets = world.entityQuery(mcontroller.position(), self.queryRange, {includedTypes = {"player","npc","monster"}})
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
  move(dt)
  self.behaviorTick = self.behaviorTick + 1
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
function table.clone(org)
  return {table.unpack(org)}
end
function addSquareLines(poly, cA, cB)
    table.insert(poly, {cA[1], cA[2]})
    table.insert(poly, {cA[1], cB[2]})
    table.insert(poly, {cB[1], cB[2]})
    table.insert(poly, {cB[1], cA[2]})
end
function makeSquare(poly, size, v)
    local cA = vec2.add(v, {size, size})
    local cB = vec2.sub(v, {size, size})
    addSquareLines(poly, cA, cB)
end
function math.round(num)
    return math.floor(num+0.5)
end
function secsToTicks(secs)
    return secs * 60
end
function queuedDebugLine(data)
    table.insert(self.debugLineQueue, data)
end
function resetQueue()
    self.debugLineQueue = {}
end
function doDebugQueue()
    local toRemove = {} -- indexes to remove from queue
    for k,v in pairs(self.debugLineQueue) do
        world.debugLine(v[1],v[2],v[3])
        v[4] = v[4] - 1
        if v[4] <= 0 then
            table.insert(toRemove, k)
        end
    end
    for k,_ in pairs(toRemove) do
        table.remove(self.debugLineQueue,toRemove[k])
        for k2,_ in pairs(toRemove) do
            toRemove[k2] = toRemove[k2] - 1
        end
    end
end
function findTileInLine(v1, v2, includeBackground) -- currently only supports lines that go up, down, diagonal, etc
    local dir = {math.max(math.min(v1[1] - v2[1], 1), -1),math.max(math.min(v1[2] - v2[2], 1), -1)}
    local dis = v1[1] - v2[1] -- how many tiles we need to iterate over
    if dis == 0 then
        dis = v1[2] - v2[2]
    end
    local v = v1
    for i = 1,dis do
        if world.tileIsOccupied(v, true) then
            return v
        elseif includeBackground and world.tileIsOccupied(v, false) then
            return v
        end
        v = vec2.add(v1, dir)
    end
    return nil
end
-- Move farthest hooks near target, make sure not too far from closest hook
function updateHooks() -- hooks will move themselves closer to boss when far enough, to prevent getting unloaded
    local nearHookRange = 50 -- maximum range Plantera can be from the closest hook if hookRestrictMode is hard restraint, if soft restraint this will divide the pull from the hooks
    local hookHoldDisMax = 0 -- if hook farther than this, move it if possible
    local hookMoveMode = 1 -- 0 chooses a point as close as possible to the target, 1 chooses a random point near the target
    local hookMoveTries = 2 -- how many times for hookMoveMode 1 to try finding a block
    local hookSearchDis = 20 -- how far max to search from the target to find a block, give up if no blocks found, is actually the size of a square instead of a circle
    local hooksAtATime = 1 -- max amount of hooks that can be moving at one time, works best with an odd number of hooks if even, and an even number of hooks if odd, or similar cases. 1 always works too
    local childrenClone = table.clone(self.children)
    if self.secondPhase then
        hooksAtATime = 1
    end
    for i,v in pairs(self.children) do
        if not world.entityExists(v) then
            replaceMinion(i)
            return
        end
    end
    local statusString = ""
    local activeHooks = 0
    for i,status in pairs(self.activeChildren) do
        if status == "moving" then -- statuses are: undefined, moving, latched, invalid
            activeHooks = activeHooks + 1
        end
        if i ~= 1 then
            statusString = statusString.."\n"
        end
        statusString = statusString.."hook "..i.." status: "..status
    end
    world.debugText(statusString, mcontroller.position(), "yellow")
    -- sort children to closest
    table.sort(childrenClone, function (a, b)
               return world.magnitude(world.entityPosition(a), mcontroller.position()) < world.magnitude(world.entityPosition(b), mcontroller.position())
            end)
        local closestValidHook = nil
        local i = 1
        local entityId = nil
    repeat
        entityId = childrenClone[i]
        i = i + 1
        local z = table.find(self.children,entityId)
        if self.activeChildren[z] ~= "moving" and self.activeChildren[z] ~= "undefined" then
            closestValidHook = entityId
        end
    until closestValidHook or i > #childrenClone
    entityId = closestValidHook
    if closestValidHook and hookRestrictMode == 0 then
        local hookPos = world.entityPosition(entityId)
        local mag = world.magnitude(hookPos, mcontroller.position()) - nearHookRange
        if mag > 0 then
            local toHook = {mag, mag}
            local dis = world.distance(hookPos, mcontroller.position())
            local angle = vec2.angle(dis)
            local calculatedAngle = {math.cos(angle), math.sin(angle)}
            local posChange = vec2.mul(toHook,calculatedAngle)
            mcontroller.setPosition(vec2.add(mcontroller.position(), posChange))
            --mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.8))
        end
    end
    if hookRestrictMode == 1 or hookRestrictMode == 2 then
        for i,v in pairs(self.children) do
            if self.activeChildren[i] ~= "moving" and self.activeChildren[i] ~= "undefined" or hookRestrictMode == 1 then
                local childPos = world.entityPosition(v)
                local mag = world.magnitude(mcontroller.position(), childPos)
                local dis = world.distance(childPos, mcontroller.position())
                local dir = vec2.angle(dis)
                local approach = {math.cos(dir), math.sin(dir)}
                local toHook = vec2.mul(approach,mag / (nearHookRange * 4))
                mcontroller.setVelocity(vec2.add(mcontroller.velocity(), toHook))
            end
        end
    end
    if activeHooks < hooksAtATime then
        -- sort children to farthest
        local farthestFrom = mcontroller.position()
        if self.targetId then
            farthestFrom = world.entityPosition(self.targetId)
        end
        table.sort(childrenClone, function (b, a)
               return world.magnitude(world.entityPosition(a), farthestFrom) < world.magnitude(world.entityPosition(b), farthestFrom)
            end)
        local farthestValidHook = nil
        local i = 1
        local entityId = nil
        local forceMoveHook = false
        local onlyMoveInvalid = false
        for _,v in pairs(childrenClone) do
            local z = table.find(self.children,v)
            if self.activeChildren[z] == "invalid" then
                onlyMoveInvalid = true
                break
            end
        end
        repeat
        entityId = childrenClone[i]
        i = i + 1
        local z = table.find(self.children,entityId)
        if self.activeChildren[z] ~= "moving" and self.activeChildren[z] ~= "undefined" then
            if self.activeChildren[z] == "invalid" then
                forceMoveHook = true
                farthestValidHook = entityId
            elseif not onlyMoveInvalid then
                farthestValidHook = entityId
            end
        end
        until farthestValidHook or i > #childrenClone
        entityId = farthestValidHook
        if farthestValidHook then
            local hookPos = world.entityPosition(entityId)
            local mag = world.magnitude(hookPos, mcontroller.position())
            if mag > hookHoldDisMax or forceMoveHook then
                local targetPos = self.targetPos
                if self.targetId then
                    targetPos = vec2.add(world.entityPosition(self.targetId), {world.entityVelocity(self.targetId)[1] * self.targetPredictMultiplier, 0})
                end
                local targetPosRounded = {math.round(targetPos[1]),math.round(targetPos[2])}
                queuedDebugLine({hookPos, targetPosRounded, "blue", 10})
                local point = nil
                local custompolies = {}
                if hookMoveMode == 0 then
                for i=0,hookSearchDis,1 do
                    local custompoly = {}
                    makeSquare(custompoly, i, targetPosRounded) -- not the most efficient method, since there's 4 lines that are actually points at the very center, but at least it's decently clean
                    table.insert(custompolies, custompoly)
                end
                
                for _,custompoly in pairs(custompolies) do
                    local lastv = custompoly[4]
                    for _,v in pairs(custompoly) do
                        if lastv then
                            queuedDebugLine({lastv, v, "blue", 10})
                            local tile
                            if self.secondPhase then
                                tile = findTileInLine(lastv, v, self.secondPhase) -- like findTileCollisionPoint but it can detect background blocks
                            else 
                                local tiles = world.lineTileCollisionPoint(lastv, v, {"Block"}) -- world.isTileOccupied can detect background blocks, but it can also detect stuff taken up by objects, so use this instead
                                if tiles then
                                    tile = tiles[1]
                                end
                            end
                            if tile then
                                point = tile
                                break
                            end
                        end
                        lastv = v
                    end
                    if point then
                        break
                    end
                end
                else
                    for i = 1,hookMoveTries do
                        local newpoint = vec2.add(targetPosRounded, {(math.random() * 2 - 1) * hookSearchDis,(math.random() * 2 - 1) * hookSearchDis})
                        queuedDebugLine({hookPos, newpoint, "blue", 10})
                        local valid = false
                        if self.secondPhase then
                            valid = world.tileIsOccupied(newpoint, true) or world.tileIsOccupied(newpoint, false)
                        else
                            valid = world.pointCollision(newpoint, {"Block"})
                        end
                        if valid then
                            point = newpoint
                            break
                        end
                    end
                end
                if point then
                    local tooclose = false
                    for _,v in pairs(self.children) do
                        if world.magnitude(world.entityPosition(v), point) < 2 then
                            tooclose = true
                        end
                    end
                    if not tooclose then
                        world.sendEntityMessage(entityId, "setTarget", point)
                    else
                        doDebugQueue()
                        resetQueue()
                    end
                else
                    doDebugQueue()
                    resetQueue()
                end
            end
        end
    end
end
function defaultMove(dt)
    self.targetPos = world.entityPosition(self.targetId)
    local targetDir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
    local myDir = mcontroller.rotation()
    local diff = rotateUtil.getRelativeAngle(targetDir, myDir)
    mcontroller.setRotation(rotateUtil.slowRotate(myDir, diff, self.baseTurnSpeed))
    self.summonTime = self.summonTime - dt
    if self.summonTime <= 0 then
        local dir = vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position()))
        local approach = {math.cos(dir), math.sin(dir)}
        local toTarget = vec2.mul(approach,1)
        local cooldowns = {1.46, 1.94, 2.92, 5.83, 0.27, 0.33, 0.44, 0.67, 1.33}
        local i = math.floor((status.resourcePercentage("health") - 0.0001) * 10)
        if self.secondPhase and i >= 5 then
            i = 4
        end
        cooldown = cooldowns[i]
        if cooldown == nil then
            cooldown = 1.17
        end
        self.summonTime = cooldown
        if not world.pointCollision({math.floor(mcontroller.position()[1]+0.5), math.floor(mcontroller.position()[2]+0.5)}, {"Block", "Dynamic", "Slippery"}) then
            if not self.secondPhase then
                local projectile = "planteraseed"
                if status.resourcePercentage("health") < 0.8 then
                    local rand = math.random(100)
                    if rand <= 25 then
                        projectile = "planterapoisonseed"
                    elseif rand > 25 and rand < 34.38 then
                        projectile = "planterathornball"
                    end
                end
                local powers = {planteraseed = 6, planterapoisonseed = 10, planterathornball = 15}
                if projectile ~= "planterathornball" then
                    animator.playSound("fire")
                end
                spawnLeveled.spawnProjectile(projectile, mcontroller.position(), entity.id(), toTarget, false, {level = self.mLevel, power=powers[projectile]})
            else
                world.sendEntityMessage(world.spawnMonster("planteraspore", mcontroller.position(), { level = self.mLevel, ownerId = entity.id() }), "damageTeam", entity.damageTeam())
            end
        end
    end
end
function transformMove()
    if not self.secondPhase then
            animator.setAnimationState("body","second")
            self.secondPhase = true
            self.approachSpeed = 0.4
            self.maxSpeed = 25
            self.baseTurnSpeed = self.baseTurnSpeed * 2
            for i=1,8,1 do
                spawnTentacle()
            end
            for _,v in pairs(self.children) do
                world.sendEntityMessage(v, "secondPhase", "")
            end
    end
end
function move(dt)
    doDebugQueue()
    local following = false
    if self.targetId == nil then
        if ownerId() then
            self.targetId = ownerId()
            following = true -- keep distance
            self.targetPos = world.entityPosition(self.targetId)
            mcontroller.setRotation(vec2.angle(world.distance(world.entityPosition(self.targetId), mcontroller.position())))
            if status.resourcePercentage("health") <= 0.5 and not self.secondPhase then
                transformMove()
                self.phase = "default"
            end
        else
            self.targetPos = vec2.add(mcontroller.position(), {0, -40})
        end
        --self.approachSpeed = 1
    else
    self.phaseTime = self.phaseTime + 1
    if status.resourcePercentage("health") <= 0.5 and not self.secondPhaseTrig then
        self.phase = "transform"
        self.phaseTime = 0
        self.speen = 0
        self.secondPhaseTrig = true
    end
    if self.phase == "default" then
        defaultMove(dt)
    end
    if self.phase == "transform" then
        transformMove()
    end
    if self.phase == "transform" then
        self.phase = "default"
    end
    end
    local decel = 0.999
    world.debugLine(mcontroller.position(), self.targetPos, "red")
    local dir = vec2.angle(world.distance(self.targetPos, mcontroller.position()))
    local approach = {math.cos(dir), math.sin(dir)}
    local approachSpeed = self.approachSpeed
    if enraged then
        approachSpeed = approachSpeed * 2
    end
    local toTarget = vec2.mul(approach,approachSpeed)
    if following then
        if world.magnitude(self.targetPos, mcontroller.position()) < 10 then
            toTarget = {0, 0}
            decel = 0.8
        end
    end
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if world.magnitude(mcontroller.velocity(), {0, 0}) > self.maxSpeed then
        mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.9))
    end
    --if self.targetId then
        updateHooks()
    --end
        if expertMode then
            if self.secondPhase then
                local liveTentacles = 0
                local deadTentacle
                for i,v in pairs(tentacles) do
                    if not world.entityExists(v) then
                        deadTentacle = i
                    else
                        liveTentacles = liveTentacles + 1
                    end
                end
                if liveTentacles < 8 then
                    replaceTentacleTimer = replaceTentacleTimer + 1
                    if replaceTentacleTimer > (5 + 5 * liveTentacles) * 60 then
                        replaceTentacle(deadTentacle)
                        replaceTentacleTimer = 0
                    end
                else
                    replaceTentacleTimer = 0
                end
            end
        end
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body", mcontroller.rotation())
end
