import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx = playdate.graphics

GameplayScene = {}
GameplayScene.__index = GameplayScene

-- screen & layout
local SCREEN_W, SCREEN_H = 400, 240
local DOCK_X, DOCK_Y = 100, 137
local OWL_X, OWL_Y = 189, 110

-- fonts
local FONT_TITLE = gfx.font.new("fonts/title")
local FONT_BODY  = gfx.font.new("fonts/body")
local function withFont(font, fn)
    local prev = gfx.getFont()
    gfx.setFont(font)
    fn()
    gfx.setFont(prev)
end

----------------------------------------------------------------
-- Fish catalog with short descriptions
----------------------------------------------------------------
local FISH = {
  {name="Bass",          rarity="Common", size={10,18}, strength=0.20, pattern="steady", desc="Reliable river resident. \nLoves shiny lures."},
  {name="Carp",          rarity="Common", size={12,22}, strength=0.30, pattern="gentle", desc="Bottom-feeder philosopher. \nSlow, steady, contemplative."},
  {name="Minnow",        rarity="Common", size={2,4},   strength=0.10, pattern="calm",   desc="Tiny but spirited. \nBlink and you’ll miss it."},
  {name="Catfish",       rarity="Medium", size={16,30}, strength=0.55, pattern="steady", desc="Whiskered bulldozer. \nLikes mud, dislikes losing."},
  {name="Trout",         rarity="Medium", size={12,20}, strength=0.45, pattern="jerky",  desc="Stream acrobat. \nSlippery, jumpy, proud of it."},
  {name="Salmon",        rarity="Medium", size={18,32}, strength=0.50, pattern="bursty", desc="Migratory muscle. \nBuilt for upstream brawls."},
  {name="Golden Koi",    rarity="Rare",   size={14,26}, strength=0.90, pattern="rhythm", desc="Regal glitter fish. \nPrefers tranquil water and applause."},
  {name="Ghost Fish",    rarity="Rare",   size={10,18}, strength=0.65, pattern="quick",  desc="You didn’t see it… \nbut it saw you."},
  {name="Flying Fish",   rarity="Rare",   size={8,14},  strength=0.40, pattern="bursty", desc="Part fish, part rumor. \nCatches air and attitudes."},
  {name="Boot Fish",     rarity="Common", size={8,8},   strength=0.15, pattern="calm",   desc="Just a soggy boot pretending\nto be a fish. Still counts!"},
  {name="Can O' Worms",  rarity="Medium", size={4,6},   strength=0.35, pattern="jerky",  desc="It opened itself. \nThat’s the problem."},
  {name="Pixel Piranha", rarity="Rare",   size={6,9},   strength=1.00, pattern="spiky",  desc="Glitched teeth with a byte.\nHandle carefully."},
  {name="Space Jelly",   rarity="Rare",   size={7,12},  strength=0.25, pattern="quick",  desc="Soft, glowy, and probably \nextraterrestrial."},
  {name="Kraken Jr.",    rarity="Medium", size={5,10},  strength=0.70, pattern="bursty", desc="Tiny tentacles, big ego. \nClaims royalty."},
}
local RARITY_WEIGHT = { Common = 0.60, Medium = 0.30, Rare = 0.10 }

-- utils
local function clamp(v, a, b) if v<a then return a elseif v>b then return v end return v end
local function lerp(a,b,t) return a + (b-a)*t end
local function slugify(name)
  return (name:lower():gsub("[^%w]+","_"):gsub("^_+",""):gsub("_+$",""):gsub("_+","_"))
end

local function pickFish()
  local r = math.random()
  local chosen = (r <= RARITY_WEIGHT.Common) and "Common"
              or (r <= RARITY_WEIGHT.Common + RARITY_WEIGHT.Medium) and "Medium" or "Rare"
  local pool = {}
  for _, f in ipairs(FISH) do if f.rarity == chosen then table.insert(pool, f) end end
  local fish = pool[math.random(#pool)]
  local minS, maxS = fish.size[1], fish.size[2]
  local sz = math.random(minS, maxS)
  return {
    name      = fish.name,
    rarity    = fish.rarity,
    sizeIn    = sz,
    strength  = fish.strength or 0.5,
    pattern   = fish.pattern  or "steady",
    desc      = fish.desc     or "One for the bucket.",
    iconSlug  = slugify(fish.name),
  }
end

----------------------------------------------------------------
-- Scene
----------------------------------------------------------------
function GameplayScene.new(manager)
  local s = setmetatable({}, GameplayScene)
  s.manager = manager

  -- background
  s.bg = gfx.image.new("images/bg_day")

  -- player poses
  s.poseImgs = {
    neutral = gfx.image.new("images/player_neutral") or gfx.image.new("images/player"),
    fish    = gfx.image.new("images/player_fish")    or gfx.image.new("images/player"),
    reel    = gfx.image.new("images/player_reel")    or gfx.image.new("images/player"),
  }

  s.player = gfx.sprite.new(s.poseImgs.neutral or gfx.image.new("images/player"))
  s.player:moveTo(DOCK_X, DOCK_Y)
  s.player:setZIndex(10)
  s.player:add()

  -- OWL (neutral/alert)
  s.owlImgs = {
    neutral = gfx.image.new("images/owl_neutral"),
    alert   = gfx.image.new("images/owl_alert"),
  }
  s.owl = gfx.sprite.new(s.owlImgs.neutral or gfx.image.new("images/owl_neutral"))
  s.owl:moveTo(OWL_X, OWL_Y)
  s.owl:setZIndex(25)
  s.owl:add()
  s.owlAlertTimer = nil

  -- state
  -- idle | waiting | hooking | reeling | bucket | catch_card | notice_card
  s.state = "idle"

  -- timers
  s.biteTimer = nil
  s.hookWindowTimer = nil
  s.catchCardTimer = nil
  s.noticeCardTimer = nil

  -- fish / reeling
  s.pendingFish = nil     -- selected while line is out, before bite
  s.currentFish = nil     -- once hooked
  s.fishDistance = 0      -- 1.0 → 0.0 to land
  s.tension = 0           -- 0..1
  s.fightTime = 0         -- seconds since start of reeling
  s._lastFrameTime = playdate.getCurrentTimeMilliseconds()

  -- tension band (player must stay between lo..hi)
  s.tensionBand = { lo = 0.35, hi = 0.65 }
  s.band = { center = 0.5, width = 0.30, amp = 0.05, freq = 1.2, phase = 0.0 }

  -- bucket (caught fish list)
  s.bucket = {}

  -- UI text
  s.statusText = nil

  -- popup card data
  s.catchInfo = nil
  s.noticeText = nil
  s.snapCard = nil      -- true when showing "the line snapped!" card

  -- icon cache
  s.iconCache = {}

  return s
end

-- background draw callback
local function drawBackground(img)
  gfx.clear()
  if img then img:draw(0, 0) end
end

function GameplayScene:enter()
  gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
    drawBackground(self.bg)
  end)
end
function GameplayScene:leave()
  gfx.sprite.setBackgroundDrawingCallback(nil)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
function GameplayScene:_setPose(which)
  local img = self.poseImgs[which]
  if img and self.player and self.player.setImage then
    self.player:setImage(img)
  elseif img and self.player then
    local x, y = self.player.x, self.player.y
    local z = self.player:getZIndex()
    self.player:remove()
    self.player = gfx.sprite.new(img)
    self.player:moveTo(x, y)
    self.player:setZIndex(z or 10)
    self.player:add()
  end
end

function GameplayScene:_setOwlPose(which)
  if not self.owl or not self.owlImgs then return end
  local img = self.owlImgs[which]
  if not img then return end
  if self.owl.setImage then
    self.owl:setImage(img)
  else
    local x, y = self.owl.x, self.owl.y
    local z = self.owl:getZIndex()
    self.owl:remove()
    self.owl = gfx.sprite.new(img)
    self.owl:moveTo(x, y)
    self.owl:setZIndex(z or 25)
    self.owl:add()
  end
end

function GameplayScene:_owlFlashAlert(ms)
  ms = ms or 4000
  self:_setOwlPose("alert")
  if self.owlAlertTimer then self.owlAlertTimer:remove() end
  self.owlAlertTimer = playdate.timer.new(ms, function()
    self:_setOwlPose("neutral")
    self.owlAlertTimer = nil
  end)
end

function GameplayScene:_clearTimers()
  if self.biteTimer then self.biteTimer:remove(); self.biteTimer = nil end
  if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
  if self.catchCardTimer then self.catchCardTimer:remove(); self.catchCardTimer = nil end
  if self.noticeCardTimer then self.noticeCardTimer:remove(); self.noticeCardTimer = nil end
  if self.owlAlertTimer then self.owlAlertTimer:remove(); self.owlAlertTimer = nil end
end

----------------------------------------------------------------
-- Casting / Bites
----------------------------------------------------------------
function GameplayScene:_castLine()
  self:_setPose("fish")
  self.state = "waiting"

  self.pendingFish = pickFish()
  print("Casting... waiting for a " .. (self.pendingFish and self.pendingFish.name or "fish") .. "...")

  local baseMs = math.random(2500, 9000)
  local rarityAdd = (self.pendingFish.rarity == "Rare" and 1600)
                 or (self.pendingFish.rarity == "Medium" and 800) or 0
  local waitMs = baseMs + rarityAdd

  self.biteTimer = playdate.timer.new(waitMs, function() self:_triggerBite() end)
end

function GameplayScene:_triggerBite()
  if self.state ~= "waiting" then return end
  self.state = "hooking"

  print((self.pendingFish and self.pendingFish.name or "A fish") .. " is biting!")

  self:_owlFlashAlert(2000)

  local minMs, maxMs = 1000, 5000
  if self.pendingFish.rarity == "Rare" then
    maxMs = 3000
  elseif self.pendingFish.rarity == "Common" then
    minMs = 1500
  end
  local window = math.random(minMs, maxMs)

  if self.pendingFish.pattern == "quick" then window = math.floor(window * 0.8) end

  self.hookWindowTimer = playdate.timer.new(window, function()
    if self.state == "hooking" then self:_endCast("Missed the hook!") end
  end)
end

function GameplayScene:_hookFish()
  if self.state ~= "hooking" then return end
  self.currentFish = self.pendingFish or pickFish()
  self.pendingFish = nil
  self.fishDistance = 1.0
  self.tension = 0.0
  self.fightTime = 0.0

  -- configure drifting tension band
  local strength = self.currentFish.strength or 0.5
  local baseWidth = 0.30 - 0.12 * strength
  baseWidth = clamp(baseWidth, 0.12, 0.30)

  local amp = 0.04 + 0.08 * strength
  amp = math.min(0.18, amp)

  local freqByPattern = {
    steady = 0.6, gentle = 0.9, calm = 0.5,
    jerky = 1.6,  bursty = 1.2, rhythm = 1.0,
    quick = 2.0,  spiky  = 1.8
  }
  local freq = freqByPattern[self.currentFish.pattern or "steady"] or 1.0

  self.band.center = clamp(0.5 + (math.random()-0.5)*0.2, 0.35, 0.65)
  self.band.width  = baseWidth
  self.band.amp    = amp
  self.band.freq   = freq
  self.band.phase  = math.random() * math.pi * 2

  local half = baseWidth * 0.5
  self.tensionBand.lo = clamp(self.band.center - half, 0.05, 0.95)
  self.tensionBand.hi = clamp(self.band.center + half, 0.05, 0.95)

  self.state = "reeling"
  self:_setPose("reel")

  local tighten = math.min(0.12, 0.12 * strength)
  self.tensionBand.lo = 0.35 + tighten
  self.tensionBand.hi = 0.65 - tighten

  print("Hooked a " .. (self.currentFish and self.currentFish.name or "fish") .. "!")
end

-- SNAP → neutral + SNAP catch card ("the line snapped!")
function GameplayScene:_snapLine()
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self.tension = 0
  self.fishDistance = 0

  self.snapCard = true
  self.catchInfo = nil      -- no fish info; this is a snap card
  self:_setPose("neutral")
  self:_setOwlPose("neutral")

  self.state = "catch_card"

  -- auto-close after ~1.6s (also closable with A)
  self.catchCardTimer = playdate.timer.new(1600, function()
    if self.state == "catch_card" and self.snapCard then
      self:_closeCatchCard()
    end
  end)

  print("Line snapped!")
end

-- CAUGHT → save to bucket, neutral + caught popup
function GameplayScene:_finishCatch()
  self:_clearTimers()
  local info = self.currentFish or pickFish()

  print("Caught a " .. (info.name or "fish") .. "!")

  table.insert(self.bucket, {
    name = info.name,
    rarity = info.rarity,
    sizeIn = info.sizeIn,
    desc = info.desc,
    iconSlug = info.iconSlug
  })

  self.currentFish = nil
  self.pendingFish = nil
  self.tension = 0
  self.fishDistance = 0

  self.snapCard = nil
  self.catchInfo = info
  self:_setPose("neutral")
  self:_setOwlPose("neutral")

  self.state = "catch_card"
end

function GameplayScene:_closeCatchCard()
  if self.catchCardTimer then
    self.catchCardTimer:remove()
    self.catchCardTimer = nil
  end
  self.catchInfo = nil
  self.snapCard = nil
  self.state = "idle"
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
end

function GameplayScene:_closeNoticeCard()
  self.noticeText = nil
  self.state = "idle"
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
end

-- ends a cast, back to idle (miss or manual cancel)
function GameplayScene:_endCast(msg)
  self.state = "idle"
  self:_clearTimers()
  self.pendingFish = nil
  self.currentFish = nil
  self:_setPose("neutral")
  self:_setOwlPose("neutral")
  self.tension = 0
  if msg then
    self.statusText = msg
    playdate.timer.new(1000, function() self.statusText = nil end)
  end
  print("Ending cast...")
end

----------------------------------------------------------------
-- Icon loader (24x24 fit) for the catch card
----------------------------------------------------------------
function GameplayScene:_getIconBySlug(slug, box)
  box = box or 24
  if not slug or slug == "" then return nil end
  self.iconCache = self.iconCache or {}
  local key = slug .. "#" .. tostring(box)
  if self.iconCache[key] ~= nil then return self.iconCache[key] end

  local candidates = {
    "images/fish/icons/" .. slug,
    "images/fish/"       .. slug,
  }

  local img = nil
  for _, path in ipairs(candidates) do
    img = gfx.image.new(path)
    if img then break end
  end

  if not img then
    img = gfx.image.new("images/fish/icons/default") or gfx.image.new("images/fish/default")
    if not img then
      print("Fish icon not found for slug: " .. slug)
      return nil
    end
  end

  local iw, ih = img:getSize()
  local scale = math.min(box / iw, box / ih, 1)
  if scale < 1 and img.scaledImage then
    img = img:scaledImage(scale)
  end

  self.iconCache[key] = img
  return img
end

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
function GameplayScene:AButtonDown()
  if self.state == "idle" then
    self:_castLine()
  elseif self.state == "waiting" then
    self:_endCast("Reeled back empty.")
  elseif self.state == "hooking" then
    if self.hookWindowTimer then self.hookWindowTimer:remove(); self.hookWindowTimer = nil end
    self:_hookFish()
  elseif self.state == "catch_card" then
    self:_closeCatchCard()
  elseif self.state == "notice_card" then
    self:_closeNoticeCard()
  elseif self.state == "bucket" then
    -- bucket stays open until B
  end
end

function GameplayScene:BButtonDown()
  if self.state == "idle" then
    self.state = "bucket"
  elseif self.state == "bucket" then
    self.state = "idle"
  end
end

----------------------------------------------------------------
-- Fight model helpers (fishPull 0..1)
----------------------------------------------------------------
function GameplayScene:_fishPullValue(dt)
  if not self.currentFish then return 0 end
  self.fightTime = self.fightTime + dt
  local t = self.fightTime
  local pat = self.currentFish.pattern

  if pat == "steady" then
    return 0.55
  elseif pat == "gentle" then
    return 0.35 + 0.15 * math.sin(t * 1.2)
  elseif pat == "calm" then
    return 0.20 + 0.10 * math.sin(t * 0.8)
  elseif pat == "jerky" then
    local base = 0.30 + 0.10 * math.sin(t * 1.3)
    if math.random() < 0.10 then base = base + 0.40 end
    return clamp(base, 0, 1)
  elseif pat == "bursty" then
    local phase = (t * 0.6) % 1.0
    local burst = (phase < 0.35) and 0.85 or 0.25
    return burst
  elseif pat == "rhythm" then
    return 0.45 + 0.35 * (0.5 + 0.5 * math.sin(t * 1.8))
  elseif pat == "quick" then
    return 0.30 + 0.40 * (0.5 + 0.5 * math.sin(t * 3.0))
  elseif pat == "spiky" then
    local base = 0.40 + 0.25 * math.sin(t * 2.5)
    if math.random() < 0.18 then base = base + 0.45 end
    return clamp(base, 0, 1)
  else
    return 0.5
  end
end

function GameplayScene:_updateTensionBand()
  local c   = self.band.center
  local w   = self.band.width
  local amp = self.band.amp
  local f   = self.band.freq
  local ph  = self.band.phase

  local drift = amp * math.sin(self.fightTime * f + ph)
  local newC  = clamp(c + drift, 0.10, 0.90)
  local half  = w * 0.5

  local lo = newC - half
  local hi = newC + half

  if lo < 0.05 then
    lo = 0.05; hi = lo + w
  elseif hi > 0.95 then
    hi = 0.95; lo = hi - w
  end

  self.tensionBand.lo = clamp(lo, 0, 1)
  self.tensionBand.hi = clamp(hi, 0, 1)
end

----------------------------------------------------------------
-- Reeling/tension update (per frame while reeling)
----------------------------------------------------------------
function GameplayScene:_updateReeling(dt)
  self:_updateTensionBand()
  local dAngle = playdate.getCrankChange() or 0
  local reelSpeed = math.abs(dAngle) / 90
  local fishPull = self:_fishPullValue(dt)
  local resist   = lerp(0.35, 1.0, fishPull)
  local strength = self.currentFish and self.currentFish.strength or 0.5

  -- tension
  if dAngle > 0 then
    self.tension = self.tension + (reelSpeed * resist * strength) * dt * 1.35
  elseif dAngle < 0 then
    local relief = (-dAngle / 90) * 0.95
    self.tension = self.tension - relief * dt
  else
    self.tension = self.tension - 0.22 * dt
  end
  self.tension = clamp(self.tension, 0, 1)

  -- progress
  local effectiveness = lerp(1.0, 0.4, fishPull)
  local baseGain = (reelSpeed * 0.020 * effectiveness) * dt * 50

  local lo, hi = self.tensionBand.lo, self.tensionBand.hi
  local inBand = (self.tension >= lo and self.tension <= hi)

  if dAngle > 0 then
    if inBand then
      self.fishDistance = clamp(self.fishDistance - baseGain, 0, 1)
    elseif self.tension < lo then
      local regress = (lo - self.tension) * (0.018 + 0.025 * fishPull) * dt * 50
      self.fishDistance = clamp(self.fishDistance + regress, 0, 1)
    else
      local tiny = baseGain * 0.25
      self.fishDistance = clamp(self.fishDistance - tiny, 0, 1)
      self.tension = clamp(self.tension + 0.20 * dt, 0, 1)
    end
  elseif dAngle < 0 then
    local give = (math.abs(dAngle) / 90) * 0.016 * dt * 50
    self.fishDistance = clamp(self.fishDistance + give, 0, 1)
  else
    if self.tension < lo then
      local creep = (lo - self.tension) * 0.010 * dt * 50
      self.fishDistance = clamp(self.fishDistance + creep, 0, 1)
    end
  end

  if self.tension >= 1.0 then
    self:_snapLine(); return
  end
  if self.fishDistance <= 0 then
    self:_finishCatch(); return
  end
end

----------------------------------------------------------------
-- Update / Draw
----------------------------------------------------------------
function GameplayScene:update()
  local nowMs = playdate.getCurrentTimeMilliseconds()
  local dt = (nowMs - (self._lastFrameTime or nowMs)) / 1000
  if dt <= 0 or dt > 0.1 then dt = 1/50 end
  self._lastFrameTime = nowMs

  if self.state == "reeling" then
    self:_updateReeling(dt)
  end

  if self.state == "reeling" then
    self:_drawTensionMeter(nowMs)
    self:_drawReelInBar()
  end

  if self.state == "bucket" then
    self:_drawBucket()
  end

  if self.statusText and self.state ~= "catch_card" and self.state ~= "notice_card" then
    gfx.drawTextAligned(self.statusText, SCREEN_W/2, 12, kTextAlignment.center)
  end

  -- IMPORTANT: draw catch card even if catchInfo is nil (snap card case)
  if self.state == "catch_card" then
    self:_drawCaughtCard(self.catchInfo)
  elseif self.state == "notice_card" and self.noticeText then
    self:_drawNoticeCard(self.noticeText)
  end
end

-- === TENSION METER (top-right) ===
function GameplayScene:_drawTensionMeter(nowMs)
  local w, h = 120, 10
  local x = SCREEN_W - w - 10
  local y = 10
  local danger = 0.85
  local now = nowMs or playdate.getCurrentTimeMilliseconds()

  -- rails
  local spacing = 6
  for i = 0, w, spacing do
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(x + i, y, x + i, y + h)
  end

  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(x-1, y-1, w+2, h+2)

  local loX = x + math.floor(w * clamp(self.tensionBand.lo, 0, 1))
  local hiX = x + math.floor(w * clamp(self.tensionBand.hi, 0, 1))
  gfx.drawLine(loX, y-3, loX, y+h+3)
  gfx.drawLine(hiX, y-3, hiX, y+h+3)

  local fillW = math.floor(w * clamp(self.tension, 0, 1))
  local shouldFlash = (self.tension >= danger) and ((math.floor(now/120) % 2) == 0)
  if fillW > 0 then
    if (self.tension < danger) or not shouldFlash then
      gfx.fillRect(x, y, fillW, h)
    end
  end
end

-- === REEL IN BAR (bottom-center; white outline + fill) ===
function GameplayScene:_drawReelInBar()
  local progress = clamp(1.0 - self.fishDistance, 0, 1)
  local w, h = 180, 8
  local x = (SCREEN_W - w) // 2
  local y = SCREEN_H - 22

  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(x-1, y-1, w+2, h+2)

  local fillW = math.floor(w * progress)
  if fillW > 0 then gfx.fillRect(x, y, fillW, h) end
end

-- === BUCKET OVERLAY ===
function GameplayScene:_drawBucket()
  local w, h = 260, 140
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2
  withFont(FONT_TITLE, function()
    gfx.drawTextAligned("BUCKET", cx, y + 8, kTextAlignment.center)
  end)

  local counts = {}
  for _, f in ipairs(self.bucket) do
    counts[f.name] = (counts[f.name] or 0) + 1
  end

  local lineY = y + 28
  local shown = 0
  if #self.bucket == 0 then
    gfx.drawTextAligned("Empty...", cx, lineY + 6, kTextAlignment.center)
  else
    for name, cnt in pairs(counts) do
      gfx.drawText("* " .. name .. " x" .. tostring(cnt), x + 12, lineY)
      lineY = lineY + 14
      shown = shown + 1
      if shown >= 7 then break end
    end
  end

  gfx.drawTextAligned("B to close", cx, y + h - 16, kTextAlignment.center)
end

-- === POPUP CARDS ===
function GameplayScene:_drawCaughtCard(info)
  local w, h = 200, 110
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2

  -- SNAP CARD
  if self.snapCard then
    withFont(FONT_TITLE, function()
      gfx.drawTextAligned("the line snapped!", cx, y + 20, kTextAlignment.center)
    end)
    withFont(FONT_BODY, function()
      gfx.drawTextAligned("ease off the crank when\n"
        .. "tension is high.", cx, y + 46, kTextAlignment.center)
    end)
    gfx.drawTextAligned("A to close", cx, y + h - 16, kTextAlignment.center)
    return
  end

  -- regular catch card (needs info)
  if not info then return end

  local title = "YOU CAUGHT A " .. string.upper(info.name)
  local desc  = info.desc or "One for the bucket."

  withFont(FONT_TITLE, function()
    gfx.drawTextAligned(title, cx, y + 10, kTextAlignment.center)
  end)
  withFont(FONT_BODY, function()
    gfx.drawTextAligned(desc,  cx, y + 34, kTextAlignment.center)
  end)

  local icon = self:_getIconBySlug(info.iconSlug, 24)
  if icon then
    local iw, ih = icon:getSize()
    icon:draw(cx - iw//2, y + h - ih - 18)
  end
end

function GameplayScene:_drawNoticeCard(text)
  local w, h = 200, 90
  local x = (SCREEN_W - w) // 2
  local y = (SCREEN_H - h) // 2

  gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(x, y, w, h)

  local cx = x + w // 2
  withFont(FONT_TITLE, function()
    gfx.drawTextAligned("The line snapped!", cx, y + 12, kTextAlignment.center)
  end)
  withFont(FONT_BODY, function()
    gfx.drawTextAligned(text or "Too much tension—ease off the crank!", cx, y + 36, kTextAlignment.center)
  end)
  gfx.drawTextAligned("A to close", cx, y + h - 14, kTextAlignment.center)
end
