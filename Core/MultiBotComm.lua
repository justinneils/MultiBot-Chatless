local MultiBot = _G.MultiBot
if not MultiBot then
  return
end

MultiBot.bridge = MultiBot.bridge or {}

local Comm = MultiBot.Comm or {}
MultiBot.Comm = Comm

Comm.prefix = "MBOT"
Comm.version = "1"

local STATE_FRAMING_CAPABILITY = "STATE_FRAMING_V1"
local STRATEGY_MUTATION_CAPABILITY = "STRATEGY_MUTATION_V1"
local STATE_TIMEOUT_SECONDS = 5.0
local STATES_TIMEOUT_SECONDS = 15.0
local STRATEGY_MUTATION_TIMEOUT_SECONDS = 5.0
local STRATEGY_MUTATION_MAX_ACTIVE = 32
local STRATEGY_MUTATION_MAX_CHANGES_LENGTH = 160
local STRATEGY_MUTATION_MAX_OPERATIONS = 32
local STRATEGY_MUTATION_MAX_STRATEGY_LENGTH = 96
local STATE_MAX_ACTIVE = 32
local STATE_MAX_BOTS = 128
local STATE_MAX_STRATEGIES_PER_SCOPE = 256
local STATE_MAX_STRATEGY_LENGTH = 192
local STATE_MAX_TOTAL_BYTES = 32768

local function safeNow()
  if type(GetTime) == "function" then
    return GetTime()
  end

  return 0
end

local function safeDelay(delaySeconds, callback)
  if type(callback) ~= "function" then
    return
  end

  if MultiBot and type(MultiBot.TimerAfter) == "function" then
    MultiBot.TimerAfter(delaySeconds or 0, callback)
    return
  end

  callback()
end

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end

  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitOnce(value, separator)
  if type(value) ~= "string" or value == "" then
    return "", ""
  end

  local startIndex, endIndex = string.find(value, separator, 1, true)
  if not startIndex then
    return value, ""
  end

  return string.sub(value, 1, startIndex - 1), string.sub(value, endIndex + 1)
end

local function splitFields(value)
  local fields = {}
  value = type(value) == "string" and value or ""
  local startIndex = 1

  while true do
    local separatorIndex = string.find(value, "~", startIndex, true)
    if not separatorIndex then
      fields[#fields + 1] = string.sub(value, startIndex)
      break
    end

    fields[#fields + 1] = string.sub(value, startIndex, separatorIndex - 1)
    startIndex = separatorIndex + 1
  end

  return fields
end

local function urlDecodeField(value)
  if type(value) ~= "string" or value == "" then
    return ""
  end

  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16) or 0)
  end))
end

local function urlEncodeField(value)
  value = tostring(value or "")
  return (value:gsub("([%%~\r\n])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

local function urlDecodeFieldStrict(value, maxLength, allowEmpty)
  if type(value) ~= "string" then
    return nil
  end

  maxLength = tonumber(maxLength or 0) or 0
  if maxLength <= 0 or #value > (maxLength * 3) then
    return nil
  end

  local output = {}
  local outputLength = 0
  local index = 1

  while index <= #value do
    local byteValue = string.byte(value, index)
    if byteValue == 37 then
      if index + 2 > #value then
        return nil
      end

      local hex = string.sub(value, index + 1, index + 2)
      if not string.match(hex, "^%x%x$") then
        return nil
      end

      byteValue = tonumber(hex, 16)
      index = index + 3
    else
      index = index + 1
    end

    if not byteValue or byteValue < 32 or byteValue == 127 then
      return nil
    end

    outputLength = outputLength + 1
    if outputLength > maxLength then
      return nil
    end

    output[#output + 1] = string.char(byteValue)
  end

  local decoded = table.concat(output)
  if decoded == "" and not allowEmpty then
    return nil
  end

  return decoded
end

local function parseBoundedInteger(value, minimum, maximum)
  value = trim(value)
  if value == "" or not string.match(value, "^%d+$") then
    return nil
  end

  local number = tonumber(value)
  if not number or number < minimum or number > maximum or math.floor(number) ~= number then
    return nil
  end

  return number
end

local function isValidStateToken(token)
  token = trim(token)
  return token ~= "" and #token <= 64 and string.match(token, "^[%w%-%_%.:]+$") ~= nil
end

local function getPlayerName()
  if type(UnitName) ~= "function" then
    return nil
  end

  local name = UnitName("player")
  if type(name) ~= "string" or name == "" then
    return nil
  end

  return name
end

local function ensureBridgeState()
  local state = MultiBot.bridge
  state.connected = state.connected or false
  state.protocol = state.protocol or nil
  state.server = state.server or nil
  state.lastSendAt = state.lastSendAt or 0
  state.lastHelloAt = state.lastHelloAt or 0
  state.lastPingAt = state.lastPingAt or 0
  state.lastPongAt = state.lastPongAt or 0
  state.lastPingToken = state.lastPingToken or nil
  state.lastError = state.lastError or nil
  state.roster = state.roster or {}
  state.states = state.states or {}
  state.stateSeq = state.stateSeq or 0
  state.stateRequests = state.stateRequests or {}
  state.stateActive = state.stateActive or {}
  state.stateLatestByBot = state.stateLatestByBot or {}
  state.stateLatestOrderByBot = state.stateLatestOrderByBot or {}
  state.stateGlobalLatestToken = state.stateGlobalLatestToken or nil
  state.stateFramingCapable = state.stateFramingCapable or false
  state.strategyMutationCapable = state.strategyMutationCapable or false
  state.strategyMutationSeq = state.strategyMutationSeq or 0
  state.strategyMutationCommands = state.strategyMutationCommands or {}
  state.weaponEnchantDebugSeq = state.weaponEnchantDebugSeq or 0
  state.details = state.details or {}
  state.professions = state.professions or {}
  state.pvpStats = state.pvpStats or {}
  state.stats = state.stats or {}
  state.quests = state.quests or {}
  state.questSeq = state.questSeq or 0
  state.questActive = state.questActive or {}
  state.gameObjects = state.gameObjects or {}
  state.gameObjectSeq = state.gameObjectSeq or 0
  state.gameObjectActive = state.gameObjectActive or {}
  state.talentSpecs = state.talentSpecs or {}
  state.talentSpecSeq = state.talentSpecSeq or 0
  state.talentSpecActive = state.talentSpecActive or nil
  state.bootstrapPending = state.bootstrapPending or false
  state.bootstrapDeadline = state.bootstrapDeadline or 0
  state.inventorySeq = state.inventorySeq or 0
  state.inventoryActive = state.inventoryActive or nil
  state.bankItems = state.bankItems or {}
  state.bankSeq = state.bankSeq or 0
  state.bankActive = state.bankActive or nil
  state.guildBankItems = state.guildBankItems or {}
  state.guildBankSeq = state.guildBankSeq or 0
  state.guildBankActive = state.guildBankActive or nil
  state.inventoryItemActionSeq = state.inventoryItemActionSeq or 0
  state.inventoryItemActions = state.inventoryItemActions or {}
  state.spellbookSeq = state.spellbookSeq or 0
  state.spellbookActive = state.spellbookActive or nil
  state.botSkills = state.botSkills or {}
  state.botSkillSeq = state.botSkillSeq or 0
  state.botSkillActive = state.botSkillActive or nil
  state.botReputations = state.botReputations or {}
  state.botReputationSeq = state.botReputationSeq or 0
  state.botReputationActive = state.botReputationActive or nil
  state.botEmblems = state.botEmblems or {}
  state.botEmblemMoney = state.botEmblemMoney or {}
  state.botEmblemSeq = state.botEmblemSeq or 0
  state.botEmblemActive = state.botEmblemActive or nil
  state.professionRecipes = state.professionRecipes or {}
  state.professionRecipeSeq = state.professionRecipeSeq or 0
  state.professionRecipeActive = state.professionRecipeActive or nil
  state.professionRecipeCraftSeq = state.professionRecipeCraftSeq or 0
  state.professionRecipeCrafts = state.professionRecipeCrafts or {}
  state.outfitSeq = state.outfitSeq or 0
  state.outfitActive = state.outfitActive or nil
  state.outfitCommands = state.outfitCommands or {}
  state.trainerSeq = state.trainerSeq or 0
  state.trainerActive = state.trainerActive or nil
  state.trainerCommands = state.trainerCommands or {}
  state.trainerSpells = state.trainerSpells or {}
  state.glyphs = state.glyphs or {}
  state.glyphSeq = state.glyphSeq or 0
  state.glyphActive = state.glyphActive or nil
  state.rtiSeq = state.rtiSeq or 0
  state.combatSeq = state.combatSeq or 0
  state.positionSeq = state.positionSeq or 0
  state.lootSeq = state.lootSeq or 0
  state.formationSeq = state.formationSeq or 0
  state.formationCommands = state.formationCommands or {}
  state.formationQuerySeq = state.formationQuerySeq or 0
  state.formationQueryActive = state.formationQueryActive or nil
  return state
end

local function countTableEntries(values)
  local count = 0
  for _ in pairs(values or {}) do
    count = count + 1
  end
  return count
end

local function stateTransactionKey(token, botName)
  return tostring(token or "") .. "\031" .. string.lower(tostring(botName or ""))
end

local function clearStateTransactionsForToken(state, token)
  for key, transaction in pairs(state.stateActive or {}) do
    if type(transaction) == "table" and transaction.token == token then
      state.stateActive[key] = nil
    end
  end
end

local function clearStateRequest(state, token)
  local request = state.stateRequests and state.stateRequests[token] or nil
  if type(request) == "table" then
    if request.global then
      if state.stateGlobalLatestToken == token then
        state.stateGlobalLatestToken = nil
      end
    else
      local botKey = string.lower(request.botName or "")
      if state.stateLatestByBot[botKey] == token then
        state.stateLatestByBot[botKey] = nil
      end
    end
  end

  clearStateTransactionsForToken(state, token)
  state.stateRequests[token] = nil
end

local function scheduleStateTimeout(token, isGlobal)
  if not (MultiBot and type(MultiBot.TimerAfter) == "function") then
    return
  end

  local timeoutSeconds = isGlobal and STATES_TIMEOUT_SECONDS or STATE_TIMEOUT_SECONDS
  MultiBot.TimerAfter(timeoutSeconds, function()
    local state = ensureBridgeState()
    if not state.stateRequests[token] then
      return
    end

    clearStateRequest(state, token)
    state.lastError = "STATE_TIMEOUT~" .. token
  end)
end

local function beginStateRequest(state, botName, isGlobal)
  if countTableEntries(state.stateRequests) >= STATE_MAX_ACTIVE then
    return nil
  end

  state.stateSeq = (tonumber(state.stateSeq) or 0) + 1
  local suffix = isGlobal and "states" or "state"
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. suffix .. "-" .. tostring(state.stateSeq)

  state.stateRequests[token] = {
    token = token,
    botName = botName or "",
    global = isGlobal == true,
    order = state.stateSeq,
    startedAt = safeNow(),
    begun = false,
    expectedBots = 0,
    completedBots = 0,
    completedBotKeys = {},
  }

  if isGlobal then
    local previous = state.stateGlobalLatestToken
    if previous and previous ~= token then
      clearStateRequest(state, previous)
    end
    state.stateGlobalLatestToken = token
  else
    local botKey = string.lower(botName or "")
    local previous = state.stateLatestByBot[botKey]
    if previous and previous ~= token then
      clearStateRequest(state, previous)
    end
    state.stateLatestByBot[botKey] = token
  end

  scheduleStateTimeout(token, isGlobal)
  return token
end

local function debugPrint(...)
  if MultiBot and MultiBot.dprint then
    MultiBot.dprint(...)
  end
end

local function L(key, fallback)
  if MultiBot and type(MultiBot.L) == "function" then
    return MultiBot.L(key, fallback)
  end

  return fallback or key
end

local function systemMessage(message)
  message = trim(message)
  if message == "" then
    return
  end

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(message)
  elseif type(print) == "function" then
    print(message)
  end
end

local function buildMessage(opcode, payload)
  local message = trim(opcode)
  if payload ~= nil and payload ~= "" then
    message = message .. "~" .. tostring(payload)
  end
  return message
end

function Comm.Send(opcode, payload)
  local state = ensureBridgeState()
  local playerName = getPlayerName()
  if not playerName or type(SendAddonMessage) ~= "function" then
    return false
  end

  local channel = "WHISPER"
  if type(GetNumRaidMembers) == "function" and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
    channel = "RAID"
  elseif type(GetNumPartyMembers) == "function" and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
    channel = "PARTY"
  end

  local message = buildMessage(opcode, payload)
  if channel == "WHISPER" then
    SendAddonMessage(Comm.prefix, message, channel, playerName)
  else
    SendAddonMessage(Comm.prefix, message, channel)
  end

  state.lastSendAt = safeNow()
  debugPrint("ADDON:TX", channel, opcode, payload or "")
  return true
end

function Comm.SendHello()
  local state = ensureBridgeState()
  state.lastHelloAt = safeNow()
  return Comm.Send("HELLO", Comm.version)
end

function Comm.SendPing()
  local state = ensureBridgeState()
  local token = tostring(math.floor(safeNow() * 1000))
  state.lastPingToken = token
  state.lastPingAt = safeNow()
  return Comm.Send("PING", token)
end

function Comm.RequestRoster()
  return Comm.Send("GET", "ROSTER")
end

function Comm.RequestState(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" then
    return false
  end

  if not state.stateFramingCapable then
    return Comm.Send("GET", "STATE~" .. name)
  end

  local token = beginStateRequest(state, name, false)
  if not token then
    state.lastError = "STATE_TOO_MANY_REQUESTS"
    return false
  end
  if not Comm.Send("GET", "STATE~" .. urlEncodeField(name) .. "~" .. token) then
    clearStateRequest(state, token)
    return false
  end

  local request = state.stateRequests[token]
  if type(request) == "table" then
    local botKey = string.lower(name)
    local requestOrder = tonumber(request.order) or 0
    local latestOrder = tonumber(state.stateLatestOrderByBot[botKey]) or 0
    if requestOrder > latestOrder then
      state.stateLatestOrderByBot[botKey] = requestOrder
    end
  end

  return token
end

function Comm.RequestStates()
  local state = ensureBridgeState()
  if not state.stateFramingCapable then
    return Comm.Send("GET", "STATES")
  end

  local token = beginStateRequest(state, "", true)
  if not token then
    state.lastError = "STATE_TOO_MANY_REQUESTS"
    return false
  end
  if not Comm.Send("GET", "STATES~" .. token) then
    clearStateRequest(state, token)
    return false
  end

  return token
end

function Comm.RequestBotDetail(name)
  name = trim(name)
  if name == "" then
    return false
  end

  return Comm.Send("GET", "DETAIL~" .. name)
end

function Comm.RequestBotDetails()
  return Comm.Send("GET", "DETAILS")
end

function Comm.RequestStats(name)
  ensureBridgeState()

  name = trim(name)
  if name ~= "" then
    return Comm.Send("GET", "STATS~" .. name)
  end

  return Comm.Send("GET", "STATS")
end

function Comm.RequestWeaponEnchantDebug(name)
  local state = ensureBridgeState()
  if not state.connected then
    state.lastError = "WEAPON_ENCHANT_NOT_CONNECTED"
    return false
  end

  name = trim(name)
  if name == "" or #name > 64 then
    state.lastError = "WEAPON_ENCHANT_BAD_BOT_NAME"
    return false
  end

  state.weaponEnchantDebugSeq = (tonumber(state.weaponEnchantDebugSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-enchant-" .. tostring(state.weaponEnchantDebugSeq)

  if not Comm.Send("GET", "WEAPON_ENCHANT~" .. urlEncodeField(name) .. "~" .. token) then
    state.lastError = "WEAPON_ENCHANT_SEND_FAILED"
    return false
  end

  return token
end

function Comm.RequestTalentSpecList(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  if name == "" then
    return false
  end

  state.talentSpecSeq = (tonumber(state.talentSpecSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.talentSpecSeq)
  state.talentSpecActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "TALENT_SPEC_LIST~" .. name .. "~" .. token) then
    state.talentSpecActive = nil
    return false
  end

  return token
end

function Comm.RunRtiCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.rtiSeq = (tonumber(state.rtiSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.rtiSeq)

  return Comm.Send("RUN", "RTI~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RunCombatCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "BOT"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.combatSeq = (tonumber(state.combatSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.combatSeq)

  return Comm.Send("RUN", "COMBAT~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

local function validateStrategyMutationChanges(changes)
  changes = trim(changes or "")
  if changes == "" or #changes > STRATEGY_MUTATION_MAX_CHANGES_LENGTH then
    return nil
  end

  local normalized = {}
  local startIndex = 1

  while true do
    local separatorIndex = string.find(changes, ",", startIndex, true)
    local operation
    if separatorIndex then
      operation = string.sub(changes, startIndex, separatorIndex - 1)
    else
      operation = string.sub(changes, startIndex)
    end

    operation = trim(operation)
    local prefix = string.sub(operation, 1, 1)
    local strategy = string.lower(trim(string.sub(operation, 2)))

    if (prefix ~= "+" and prefix ~= "-")
        or strategy == ""
        or #strategy > STRATEGY_MUTATION_MAX_STRATEGY_LENGTH
        or string.find(strategy, "[^%w%s%-%_']") then
      return nil
    end

    normalized[#normalized + 1] = prefix .. strategy
    if #normalized > STRATEGY_MUTATION_MAX_OPERATIONS then
      return nil
    end

    if not separatorIndex then
      break
    end
    startIndex = separatorIndex + 1
  end

  if #normalized == 0 then
    return nil
  end

  return table.concat(normalized, ",")
end

local function finishStrategyMutationCommand(token, result)
  local state = ensureBridgeState()
  local pending = state.strategyMutationCommands[token]
  if type(pending) ~= "table" then
    return false
  end

  state.strategyMutationCommands[token] = nil
  result = type(result) == "table" and result or {}
  result.token = token
  result.scope = result.scope or pending.scope
  result.target = result.target or pending.target
  result.stateScope = result.stateScope or pending.stateScope
  result.changes = result.changes or pending.changes

  if type(pending.callback) == "function" then
    pending.callback(result)
  end

  if MultiBot.OnStrategyMutationApplied then
    MultiBot.OnStrategyMutationApplied(result)
  end

  return true
end

function Comm.RunStrategyCommand(scope, target, stateScope, changes, callback)
  local state = ensureBridgeState()

  if not state.connected then
    state.lastError = "STRATEGY_NOT_CONNECTED"
    return false
  end
  if not state.strategyMutationCapable then
    state.lastError = "STRATEGY_CAPABILITY_UNAVAILABLE"
    return false
  end

  scope = string.upper(trim(scope or "BOT"))
  target = trim(target or "")
  stateScope = string.upper(trim(stateScope or ""))
  changes = validateStrategyMutationChanges(changes)

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "PARTY" and scope ~= "RAID" and scope ~= "BOT" then
    state.lastError = "STRATEGY_INVALID_SCOPE"
    return false
  end
  if scope == "BOT" and target == "" then
    state.lastError = "STRATEGY_TARGET_REQUIRED"
    return false
  end
  if scope ~= "BOT" and target ~= "" then
    state.lastError = "STRATEGY_TARGET_NOT_ALLOWED"
    return false
  end
  if stateScope ~= "C" and stateScope ~= "N" then
    state.lastError = "STRATEGY_INVALID_STATE_SCOPE"
    return false
  end
  if not changes then
    state.lastError = "STRATEGY_INVALID_CHANGES"
    return false
  end
  if countTableEntries(state.strategyMutationCommands) >= STRATEGY_MUTATION_MAX_ACTIVE then
    state.lastError = "STRATEGY_TOO_MANY_REQUESTS"
    return false
  end

  state.strategyMutationSeq = (tonumber(state.strategyMutationSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-strategy-" .. tostring(state.strategyMutationSeq)
  state.strategyMutationCommands[token] = {
    scope = scope,
    target = target,
    stateScope = stateScope,
    changes = changes,
    callback = type(callback) == "function" and callback or nil,
    startedAt = safeNow(),
  }

  local payload = "STRATEGY~"
    .. scope .. "~"
    .. urlEncodeField(target) .. "~"
    .. token .. "~"
    .. stateScope .. "~"
    .. urlEncodeField(changes)

  if not Comm.Send("RUN", payload) then
    state.strategyMutationCommands[token] = nil
    state.lastError = "STRATEGY_SEND_FAILED"
    return false
  end

  if MultiBot and type(MultiBot.TimerAfter) == "function" then
    MultiBot.TimerAfter(STRATEGY_MUTATION_TIMEOUT_SECONDS, function()
      local bridge = ensureBridgeState()
      if not bridge.strategyMutationCommands[token] then
        return
      end

      bridge.lastError = "STRATEGY_TIMEOUT~" .. token
      finishStrategyMutationCommand(token, {
        status = "timeout",
        matched = 0,
        succeeded = 0,
        failed = 0,
        reason = "TIMEOUT",
      })
    end)
  end

  return token
end

function Comm.RunLootCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.lootSeq = (tonumber(state.lootSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-loot-" .. tostring(state.lootSeq)

  return Comm.Send("RUN", "LOOT~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RunPositionCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.positionSeq = (tonumber(state.positionSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-position-" .. tostring(state.positionSeq)

  return Comm.Send("RUN", "POSITION~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

-- Necro-Network graveyard hop. Unlike the other RUN verbs this acts on the
-- requesting player rather than on bots, so it takes no scope or target.
-- Wire shape: GRAVEYARD~<id>~<token>
function Comm.RunGraveyardCommand(graveyardId)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  graveyardId = tonumber(graveyardId)
  if not graveyardId or graveyardId <= 0 then
    return false
  end

  state.graveyardSeq = (tonumber(state.graveyardSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-graveyard-" .. tostring(state.graveyardSeq)

  return Comm.Send("RUN", "GRAVEYARD~" .. tostring(math.floor(graveyardId)) .. "~" .. token)
end

function Comm.RunFormationCommand(scope, target, formation, callback)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  scope = string.upper(trim(scope or "GROUP"))
  target = trim(target or "")
  formation = string.lower(trim(formation or ""))

  local allowed = {
    arrow = true,
    queue = true,
    near = true,
    melee = true,
    line = true,
    circle = true,
    chaos = true,
    shield = true,
    -- Local addition: mod-playerbots' ninth formation. Must stay in step with the
    -- button list in MultiBotFormationUI.lua and with IsAllowedFormationName in
    -- mod-multibot-bridge, or the bridge rejects it.
    far = true,
  }

  if scope ~= "GROUP" or target ~= "" or not allowed[formation] then
    return false
  end

  state.formationSeq = (tonumber(state.formationSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-formation-" .. tostring(state.formationSeq)
  state.formationCommands[token] = {
    formation = formation,
    callback = type(callback) == "function" and callback or nil,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "FORMATION~" .. scope .. "~~" .. token .. "~" .. urlEncodeField(formation)) then
    state.formationCommands[token] = nil
    return false
  end

  if MultiBot and type(MultiBot.TimerAfter) == "function" then
    MultiBot.TimerAfter(5.0, function()
      local bridge = ensureBridgeState()
      local pending = bridge.formationCommands[token]
      if not pending then
        return
      end

      bridge.formationCommands[token] = nil
      local result = {
        status = "timeout",
        scope = scope,
        target = target,
        token = token,
        success = 0,
        failure = 0,
        formation = formation,
      }

      if type(pending.callback) == "function" then
        pending.callback(result)
      end

      if MultiBot.OnFormationCommandApplied then
        MultiBot.OnFormationCommandApplied(result)
      end

      systemMessage(L("formation.confirm.timeout"))
    end)
  end

  return token
end

function Comm.RequestFormations(callback)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  state.formationQuerySeq = (tonumber(state.formationQuerySeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-formations-" .. tostring(state.formationQuerySeq)

  state.formationQueryActive = {
    token = token,
    callback = type(callback) == "function" and callback or nil,
    startedAt = safeNow(),
    expected = 0,
    items = {},
    begun = false,
  }

  if not Comm.Send("GET", "FORMATIONS~GROUP~~" .. token) then
    state.formationQueryActive = nil
    return false
  end

  if MultiBot and type(MultiBot.TimerAfter) == "function" then
    MultiBot.TimerAfter(5.0, function()
      local bridge = ensureBridgeState()
      local active = bridge.formationQueryActive
      if not active or active.token ~= token then
        return
      end

      bridge.formationQueryActive = nil
      local result = {
        token = token,
        status = "timeout",
        expected = tonumber(active.expected or 0) or 0,
        sent = #(active.items or {}),
        items = active.items or {},
      }

      if type(active.callback) == "function" then
        active.callback(result)
      end

      if MultiBot.OnFormationQueryCompleted then
        MultiBot.OnFormationQueryCompleted(result)
      end
    end)
  end

  return token
end

local function getActiveFormationQuery(token)
  local active = ensureBridgeState().formationQueryActive
  token = trim(token)

  if type(active) ~= "table" or token == "" or active.token ~= token then
    return nil
  end

  return active
end

function Comm.ApplyFormationsBeginPayload(payload)
  local token, countText = splitOnce(payload or "", "~")
  token = trim(token)

  local active = getActiveFormationQuery(token)
  if not active then
    return false
  end

  active.expected = tonumber(countText or "0") or 0
  active.items = {}
  active.begun = true

  debugPrint("ADDON:RX", "FORMATIONS_BEGIN", token, active.expected)
  return true
end

function Comm.ApplyFormationsItemPayload(payload)
  local token, rest = splitOnce(payload or "", "~")
  local encodedBotName, encodedFormation = splitOnce(rest or "", "~")
  token = trim(token)

  local active = getActiveFormationQuery(token)
  if not active or not active.begun then
    return false
  end

  local botName = trim(urlDecodeField(encodedBotName))
  local formation = string.lower(trim(urlDecodeField(encodedFormation)))

  if botName == "" then
    return false
  end

  if formation == "" then
    formation = "?"
  end

  active.items[#active.items + 1] = {
    botName = botName,
    formation = formation,
  }

  debugPrint("ADDON:RX", "FORMATIONS_ITEM", token, botName, formation)
  return true
end

function Comm.ApplyFormationsEndPayload(payload)
  local token, sentText = splitOnce(payload or "", "~")
  token = trim(token)

  local state = ensureBridgeState()
  local active = getActiveFormationQuery(token)
  if not active or not active.begun then
    return false
  end

  table.sort(active.items, function(left, right)
    return string.lower(left.botName or "") < string.lower(right.botName or "")
  end)

  state.formationQueryActive = nil

  local result = {
    token = token,
    status = "ok",
    expected = tonumber(active.expected or 0) or 0,
    sent = tonumber(sentText or "0") or 0,
    items = active.items or {},
  }

  debugPrint("ADDON:RX", "FORMATIONS_END", token, result.sent)

  if type(active.callback) == "function" then
    active.callback(result)
  end

  if MultiBot.OnFormationQueryCompleted then
    MultiBot.OnFormationQueryCompleted(result)
  end

  return true
end

function Comm.RequestOutfits(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.outfitSeq = (tonumber(state.outfitSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.outfitSeq)
  state.outfitActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    lines = {},
  }

  if not Comm.Send("GET", "OUTFITS~" .. name .. "~" .. token) then
    state.outfitActive = nil
    return false
  end

  return true
end

function Comm.RunOutfitCommand(name, commandSuffix, persist)
  local state = ensureBridgeState()
  name = trim(name)
  commandSuffix = trim(commandSuffix)
  if name == "" or commandSuffix == "" or not state.connected then
    return false
  end

  state.outfitSeq = (tonumber(state.outfitSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-cmd-" .. tostring(state.outfitSeq)
  state.outfitCommands[token] = {
    botName = name,
    botNameKey = string.lower(name),
    command = commandSuffix,
    startedAt = safeNow(),
  }

  local persistToken = persist and "1" or "0"
  if not Comm.Send("RUN", "OUTFIT~" .. name .. "~" .. token .. "~" .. urlEncodeField(commandSuffix) .. "~" .. persistToken) then
    state.outfitCommands[token] = nil
    return false
  end

  return true
end

function Comm.RequestTrainer(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.trainerSeq = (tonumber(state.trainerSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-trainer-" .. tostring(state.trainerSeq)
  state.trainerActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    trainerEntry = 0,
    trainerName = "",
    startedAt = safeNow(),
    spells = {},
  }

  if not Comm.Send("GET", "TRAINER~" .. name .. "~" .. token) then
    state.trainerActive = nil
    return false
  end

  return true
end

function Comm.RunTrainerLearn(name, trainerEntry, spellId)
  local state = ensureBridgeState()
  name = trim(name)
  trainerEntry = tonumber(trainerEntry or 0) or 0

  local spellToken = trim(spellId)
  if spellToken == "" and tonumber(spellId or 0) then
    spellToken = tostring(tonumber(spellId or 0) or 0)
  end
  if string.upper(spellToken) ~= "ALL" then
    local numericSpellId = tonumber(spellToken or "0") or 0
    if numericSpellId <= 0 then
      return false
    end
    spellToken = tostring(numericSpellId)
  else
    spellToken = "ALL"
  end

  if name == "" or trainerEntry <= 0 or not state.connected then
    return false
  end

  state.trainerSeq = (tonumber(state.trainerSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-trainer-learn-" .. tostring(state.trainerSeq)
  state.trainerCommands[token] = {
    botName = name,
    botNameKey = string.lower(name),
    trainerEntry = trainerEntry,
    spellId = spellToken,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "TRAINER_LEARN~" .. name .. "~" .. token .. "~" .. trainerEntry .. "~" .. spellToken) then
    state.trainerCommands[token] = nil
    return false
  end

  return true
end

function Comm.RequestGlyphs(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  if name == "" then
    return false
  end

  state.glyphSeq = (tonumber(state.glyphSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.glyphSeq)
  state.glyphActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "GLYPHS~" .. name .. "~" .. token) then
    state.glyphActive = nil
    return false
  end

  return token
end

function Comm.RequestQuests(mode, name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  mode = string.upper(trim(mode or "ALL"))
  if mode ~= "INCOMPLETED" and mode ~= "COMPLETED" and mode ~= "ALL" then
    mode = "ALL"
  end

  name = trim(name)
  state.questSeq = (tonumber(state.questSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.questSeq)

  state.questActive[token] = {
    mode = mode,
    botName = name,
    isGroup = name == "",
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "QUESTS~" .. mode .. "~" .. name .. "~" .. token) then
    state.questActive[token] = nil
    return false
  end

  return token
end

function Comm.RequestGameObjects(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  state.gameObjectSeq = (tonumber(state.gameObjectSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-gob-" .. tostring(state.gameObjectSeq)

  state.gameObjectActive[token] = {
    botName = name,
    isGroup = name == "",
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "GAMEOBJECTS~" .. name .. "~" .. token) then
    state.gameObjectActive[token] = nil
    return false
  end

  return token
end

function Comm.RequestPvpStats(name)
  ensureBridgeState()

  name = trim(name)
  if name ~= "" then
    return Comm.Send("GET", "PVP_STATS~" .. name)
  end

  return Comm.Send("GET", "PVP_STATS")
end

function Comm.RequestInventory(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.inventorySeq = (tonumber(state.inventorySeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.inventorySeq)
  state.inventoryActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "INVENTORY~" .. name .. "~" .. token) then
    state.inventoryActive = nil
    return false
  end

  return true
end

function Comm.RequestBank(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.bankSeq = (tonumber(state.bankSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-bank-" .. tostring(state.bankSeq)
  state.bankActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    error = nil,
  }

  if not Comm.Send("GET", "BANK~" .. name .. "~" .. token) then
    state.bankActive = nil
    return false
  end

  return token
end

function Comm.RequestGuildBank(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.guildBankSeq = (tonumber(state.guildBankSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-gbank-" .. tostring(state.guildBankSeq)
  state.guildBankActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    error = nil,
  }

  if not Comm.Send("GET", "GBANK~" .. name .. "~" .. token) then
    state.guildBankActive = nil
    return false
  end

  return token
end

function Comm.RequestSpellbook(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.spellbookSeq = (tonumber(state.spellbookSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.spellbookSeq)
  state.spellbookActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "SPELLBOOK~" .. name .. "~" .. token) then
    state.spellbookActive = nil
    return false
  end

  return true
end

function Comm.RequestBotSkills(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botSkillSeq = (tonumber(state.botSkillSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.botSkillSeq)
  state.botSkillActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
  }

  if not Comm.Send("GET", "BOT_SKILLS~" .. name .. "~" .. token) then
    state.botSkillActive = nil
    return false
  end

  return true
end

function Comm.RequestBotReputations(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botReputationSeq = (tonumber(state.botReputationSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-rep-" .. tostring(state.botReputationSeq)
  state.botReputationActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
  }

  if not Comm.Send("GET", "BOT_REPUTATIONS~" .. name .. "~" .. token) then
    state.botReputationActive = nil
    return false
  end

  return true
end

function Comm.RequestBotEmblems(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botEmblemSeq = (tonumber(state.botEmblemSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-emblem-" .. tostring(state.botEmblemSeq)
  state.botEmblemActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    money = nil,
  }

  if not Comm.Send("GET", "BOT_EMBLEMS~" .. name .. "~" .. token) then
    state.botEmblemActive = nil
    return false
  end

  return true
end

function Comm.RequestProfessionRecipes(name, skillId)
  local state = ensureBridgeState()
  name = trim(name)
  skillId = tonumber(skillId or 0) or 0
  if name == "" or skillId <= 0 or not state.connected then
    return false
  end

  state.professionRecipeSeq = (tonumber(state.professionRecipeSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.professionRecipeSeq)
  state.professionRecipeActive = {
    botName = name,
    botNameKey = string.lower(name),
    skillId = skillId,
    token = token,
    startedAt = safeNow(),
    recipes = {},
  }

  if not Comm.Send("GET", "PROFESSION_RECIPES~" .. name .. "~" .. skillId .. "~" .. token) then
    state.professionRecipeActive = nil
    return false
  end

  return true
end

function Comm.RunProfessionRecipeCraft(name, skillId, spellId, itemId)
  local state = ensureBridgeState()
  name = trim(name)
  skillId = tonumber(skillId or 0) or 0
  spellId = tonumber(spellId or 0) or 0
  itemId = tonumber(itemId or 0) or 0
  if name == "" or skillId <= 0 or spellId <= 0 or itemId < 0 or not state.connected then
    return false
  end

  state.professionRecipeCraftSeq = (tonumber(state.professionRecipeCraftSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-craft-" .. tostring(state.professionRecipeCraftSeq)
  state.professionRecipeCrafts[token] = {
    botName = name,
    botNameKey = string.lower(name),
    skillId = skillId,
    spellId = spellId,
    itemId = itemId,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "CRAFT_RECIPE~" .. name .. "~" .. token .. "~" .. skillId .. "~" .. spellId .. "~" .. itemId) then
    state.professionRecipeCrafts[token] = nil
    return false
  end

  return token
end

function Comm.RunInventoryItemAction(name, action, itemId, count)
  local state = ensureBridgeState()
  name = trim(name)
  action = string.upper(trim(action))
  itemId = tonumber(itemId or 0) or 0
  count = tonumber(count or 0) or 0
  if name == "" or action == "" or itemId <= 0 or count < 0 or not state.connected then
    return false
  end

  state.inventoryItemActionSeq = (tonumber(state.inventoryItemActionSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-item-" .. tostring(state.inventoryItemActionSeq)
  state.inventoryItemActions[token] = {
    botName = name,
    botNameKey = string.lower(name),
    action = action,
    itemId = itemId,
    count = count,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "ITEM_ACTION~" .. name .. "~" .. token .. "~" .. action .. "~" .. itemId .. "~" .. count) then
    state.inventoryItemActions[token] = nil
    return false
  end

  return token
end

function Comm.MarkDisconnected(reason)
  local state = ensureBridgeState()
  state.connected = false
  state.server = nil
  state.protocol = nil
  state.lastError = reason or nil
  state.inventoryActive = nil
  state.bankActive = nil
  state.guildBankActive = nil
  state.inventoryItemActions = {}
  state.spellbookActive = nil
  state.botSkillActive = nil
  state.botReputationActive = nil
  state.botEmblemActive = nil
  state.professionRecipeActive = nil
  state.professionRecipeCrafts = {}
  state.outfitActive = nil
  state.outfitCommands = {}
  state.trainerActive = nil
  state.trainerCommands = {}
  state.formationCommands = {}
  state.formationQueryActive = nil
  state.strategyMutationCapable = false
  state.stateFramingCapable = false

  local pendingTokens = {}
  for token in pairs(state.strategyMutationCommands or {}) do
    pendingTokens[#pendingTokens + 1] = token
  end
  for _, token in ipairs(pendingTokens) do
    finishStrategyMutationCommand(token, {
      status = "error",
      matched = 0,
      succeeded = 0,
      failed = 0,
      reason = "DISCONNECTED",
    })
  end
  state.strategyMutationCommands = {}

  state.stateRequests = {}
  state.stateActive = {}
  state.stateLatestByBot = {}
  state.stateLatestOrderByBot = {}
  state.stateGlobalLatestToken = nil
end

local function parseBridgeDetailPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local race, rest2 = splitOnce(rest or "", "~")
  local gender, rest3 = splitOnce(rest2 or "", "~")
  local className, rest4 = splitOnce(rest3 or "", "~")
  local level, rest5 = splitOnce(rest4 or "", "~")
  local talent1, rest6 = splitOnce(rest5 or "", "~")
  local talent2, rest7 = splitOnce(rest6 or "", "~")
  local talent3, score = splitOnce(rest7 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    race = urlDecodeField(race),
    gender = urlDecodeField(gender),
    className = urlDecodeField(className),
    level = tonumber(level or "0") or 0,
    talent1 = tonumber(talent1 or "0") or 0,
    talent2 = tonumber(talent2 or "0") or 0,
    talent3 = tonumber(talent3 or "0") or 0,
    score = tonumber(score or "0") or 0,
    lastUpdateAt = safeNow(),
  }
end

local function parseBridgeProfessionPayload(payload)
  local name, professionPayload = splitOnce(payload or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  local professions = {}
  for token in string.gmatch(professionPayload or "", "([^;]+)") do
    token = trim(urlDecodeField(token))

    local profession, value = splitOnce(token, ":")
    profession = string.lower(trim(profession or ""))

    if profession ~= "" then
      professions[profession] = value ~= "" and value or true
    end
  end

  return {
    name = name,
    professions = professions,
    lastUpdateAt = safeNow(),
  }
end

local function parseRosterEntry(entry)
  local fields = {}
  for value in string.gmatch(entry or "", "([^,]+)") do
    fields[#fields + 1] = value
  end

  return {
    name = fields[1],
    classId = tonumber(fields[2] or "0") or 0,
    level = tonumber(fields[3] or "0") or 0,
    mapId = tonumber(fields[4] or "0") or 0,
    alive = fields[5] == "1",
    hpPct = tonumber(fields[6] or "0") or 0,
    mpPct = tonumber(fields[7] or "0") or 0,
  }
end

function Comm.ApplyRosterPayload(payload)
  local state = ensureBridgeState()
  local roster = {}

  if type(payload) == "string" and payload ~= "" then
    for entry in string.gmatch(payload, "([^;]+)") do
      roster[#roster + 1] = parseRosterEntry(entry)
    end
  end

  state.roster = roster

  if MultiBot.SyncBridgeRosterToPlayers then
    MultiBot.SyncBridgeRosterToPlayers(roster)
  end

  if state.connected and Comm.RequestBotDetails then
    Comm.RequestBotDetails()
  end

  debugPrint("ADDON:RX", "ROSTER", tostring(#roster))
  return roster
end

local function applyStateEntry(name, combat, normal)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" then
    return nil
  end

  local entry = {
    name = name,
    combat = combat or "",
    normal = normal or "",
    lastUpdateAt = safeNow(),
  }

  state.states[string.lower(name)] = entry

  if MultiBot.ApplyBridgeBotState then
    MultiBot.ApplyBridgeBotState(name, entry.combat, entry.normal)
  end

  debugPrint("ADDON:RX", "STATE", name, entry.combat, entry.normal)
  return entry
end

function Comm.ApplyStatePayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local combat, normal = splitOnce(rest or "", "~")
  return applyStateEntry(name, combat, normal)
end

function Comm.ApplyStatesPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^;]+)") do
      if Comm.ApplyStatePayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "STATES", tostring(applied))
  return applied
end

local function getStateRequest(token)
  local state = ensureBridgeState()
  token = trim(token)
  if not isValidStateToken(token) then
    return nil
  end
  return state.stateRequests[token]
end

local function abortStateRequest(token, reason)
  local state = ensureBridgeState()
  token = trim(token)
  if token == "" then
    return false
  end

  clearStateRequest(state, token)
  state.lastError = "STATE_ABORT~" .. token .. "~" .. tostring(reason or "UNKNOWN")
  debugPrint("ADDON:RX", "STATE_ABORT", token, reason or "UNKNOWN")
  return true
end

function Comm.ApplyStateBeginPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 4 then
    return false
  end

  local token = trim(fields[1])
  local botName = urlDecodeFieldStrict(fields[2], 64, false)
  local combatCount = parseBoundedInteger(fields[3], 0, STATE_MAX_STRATEGIES_PER_SCOPE)
  local normalCount = parseBoundedInteger(fields[4], 0, STATE_MAX_STRATEGIES_PER_SCOPE)
  local state = ensureBridgeState()
  local request = getStateRequest(token)

  if not request or not botName or combatCount == nil or normalCount == nil then
    return false
  end

  local botKey = string.lower(botName)
  if request.global then
    if not request.begun then
      return abortStateRequest(token, "GLOBAL_NOT_BEGUN")
    end
    if request.completedBotKeys[botKey] then
      return abortStateRequest(token, "DUPLICATE_BOT")
    end
  elseif string.lower(request.botName or "") ~= botKey then
    return abortStateRequest(token, "BOT_MISMATCH")
  end

  local key = stateTransactionKey(token, botName)
  if state.stateActive[key] then
    return abortStateRequest(token, "DUPLICATE_BEGIN")
  end

  if countTableEntries(state.stateActive) >= STATE_MAX_ACTIVE then
    return abortStateRequest(token, "TOO_MANY_ACTIVE")
  end

  state.stateActive[key] = {
    token = token,
    botName = botName,
    botKey = botKey,
    combatExpected = combatCount,
    normalExpected = normalCount,
    combatReceived = 0,
    normalReceived = 0,
    combat = {},
    normal = {},
    totalBytes = 0,
  }

  debugPrint("ADDON:RX", "STATE_BEGIN", token, botName, combatCount, normalCount)
  return true
end

function Comm.ApplyStateItemPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 5 then
    return false
  end

  local token = trim(fields[1])
  local botName = urlDecodeFieldStrict(fields[2], 64, false)
  local scope = string.upper(trim(fields[3]))
  local index = parseBoundedInteger(fields[4], 1, STATE_MAX_STRATEGIES_PER_SCOPE)
  local strategy = urlDecodeFieldStrict(fields[5], STATE_MAX_STRATEGY_LENGTH, false)
  if not botName or not index or not strategy or (scope ~= "C" and scope ~= "N") then
    return false
  end

  local state = ensureBridgeState()
  local transaction = state.stateActive[stateTransactionKey(token, botName)]
  if not transaction then
    return false
  end

  local expected = scope == "C" and transaction.combatExpected or transaction.normalExpected
  local items = scope == "C" and transaction.combat or transaction.normal
  if index > expected then
    return abortStateRequest(token, "INDEX_OUT_OF_RANGE")
  end

  if items[index] ~= nil then
    if items[index] == strategy then
      return true
    end
    return abortStateRequest(token, "CONFLICTING_DUPLICATE")
  end

  transaction.totalBytes = transaction.totalBytes + #strategy
  if transaction.totalBytes > STATE_MAX_TOTAL_BYTES then
    return abortStateRequest(token, "STATE_TOO_LARGE")
  end

  items[index] = strategy
  if scope == "C" then
    transaction.combatReceived = transaction.combatReceived + 1
  else
    transaction.normalReceived = transaction.normalReceived + 1
  end

  debugPrint("ADDON:RX", "STATE_ITEM", token, botName, scope, index, strategy)
  return true
end

function Comm.ApplyStateEndPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 4 then
    return false
  end

  local token = trim(fields[1])
  local botName = urlDecodeFieldStrict(fields[2], 64, false)
  local combatCount = parseBoundedInteger(fields[3], 0, STATE_MAX_STRATEGIES_PER_SCOPE)
  local normalCount = parseBoundedInteger(fields[4], 0, STATE_MAX_STRATEGIES_PER_SCOPE)
  if not botName or combatCount == nil or normalCount == nil then
    return false
  end

  local state = ensureBridgeState()
  local key = stateTransactionKey(token, botName)
  local transaction = state.stateActive[key]
  local request = getStateRequest(token)
  if not transaction or not request then
    return false
  end

  if combatCount ~= transaction.combatExpected or normalCount ~= transaction.normalExpected or
      transaction.combatReceived ~= combatCount or transaction.normalReceived ~= normalCount then
    return abortStateRequest(token, "COUNT_MISMATCH")
  end

  for index = 1, combatCount do
    if transaction.combat[index] == nil then
      return abortStateRequest(token, "MISSING_COMBAT_ITEM")
    end
  end
  for index = 1, normalCount do
    if transaction.normal[index] == nil then
      return abortStateRequest(token, "MISSING_NORMAL_ITEM")
    end
  end

  if request.global then
    if state.stateGlobalLatestToken ~= token then
      return abortStateRequest(token, "STALE_GLOBAL")
    end
  elseif state.stateLatestByBot[transaction.botKey] ~= token then
    return abortStateRequest(token, "STALE_BOT")
  end

  local requestOrder = tonumber(request.order) or 0
  local latestOrder = tonumber(state.stateLatestOrderByBot[transaction.botKey]) or 0
  if requestOrder < latestOrder then
    state.stateActive[key] = nil
    if request.global then
      if not request.completedBotKeys[transaction.botKey] then
        request.completedBotKeys[transaction.botKey] = true
        request.completedBots = request.completedBots + 1
      end
    else
      clearStateRequest(state, token)
    end

    debugPrint("ADDON:RX", "STATE_END_STALE", token, botName, requestOrder, latestOrder)
    return true
  end

  state.stateLatestOrderByBot[transaction.botKey] = requestOrder

  local entry = applyStateEntry(transaction.botName, table.concat(transaction.combat, ", "), table.concat(transaction.normal, ", "))
  if not entry then
    return abortStateRequest(token, "APPLY_FAILED")
  end

  state.stateActive[key] = nil
  if request.global then
    if not request.completedBotKeys[transaction.botKey] then
      request.completedBotKeys[transaction.botKey] = true
      request.completedBots = request.completedBots + 1
    end
  else
    clearStateRequest(state, token)
  end

  debugPrint("ADDON:RX", "STATE_END", token, botName, combatCount, normalCount)
  return true
end

function Comm.ApplyStateAbortPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 3 then
    return false
  end

  local token = trim(fields[1])
  local reason = urlDecodeFieldStrict(fields[3], 64, false) or "UNKNOWN"
  if not getStateRequest(token) then
    return false
  end

  return abortStateRequest(token, reason)
end

function Comm.ApplyStatesBeginPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 2 then
    return false
  end

  local token = trim(fields[1])
  local botCount = parseBoundedInteger(fields[2], 0, STATE_MAX_BOTS)
  local request = getStateRequest(token)
  if not request or not request.global or botCount == nil or request.begun then
    return false
  end

  request.begun = true
  request.expectedBots = botCount
  request.completedBots = 0
  request.completedBotKeys = {}
  debugPrint("ADDON:RX", "STATES_BEGIN", token, botCount)
  return true
end

function Comm.ApplyStatesEndPayload(payload)
  local fields = splitFields(payload)
  if #fields ~= 2 then
    return false
  end

  local token = trim(fields[1])
  local sentCount = parseBoundedInteger(fields[2], 0, STATE_MAX_BOTS)
  local state = ensureBridgeState()
  local request = getStateRequest(token)
  if not request or not request.global or not request.begun or sentCount == nil then
    return false
  end

  for _, transaction in pairs(state.stateActive) do
    if type(transaction) == "table" and transaction.token == token then
      return abortStateRequest(token, "INCOMPLETE_TRANSACTION")
    end
  end

  if sentCount ~= request.expectedBots or request.completedBots ~= request.expectedBots then
    return abortStateRequest(token, "GLOBAL_COUNT_MISMATCH")
  end

  clearStateRequest(state, token)
  debugPrint("ADDON:RX", "STATES_END", token, sentCount)
  return true
end

function Comm.ApplyBotDetailPayload(payload)
  local state = ensureBridgeState()
  local detail = parseBridgeDetailPayload(payload)
  if not detail then
    return nil
  end

  local key = string.lower(detail.name)
  local existing = state.details[key]
  local professionEntry = state.professions[key]

  if type(existing) == "table" and type(existing.professions) == "table" then
    detail.professions = existing.professions
  end

  if type(professionEntry) == "table" and type(professionEntry.professions) == "table" then
    detail.professions = professionEntry.professions
  end

  state.details[key] = detail

  if MultiBot.ApplyBridgeBotDetail then
    MultiBot.ApplyBridgeBotDetail(detail)
  end

  debugPrint("ADDON:RX", "DETAIL", detail.name, detail.className or "", tostring(detail.level or 0), tostring(detail.score or 0))
  return detail
end

function Comm.ApplyBotProfessionPayload(payload)
  local state = ensureBridgeState()
  local entry = parseBridgeProfessionPayload(payload)
  if not entry then
    return nil
  end

  local key = string.lower(entry.name)
  state.professions[key] = entry

  local detail = state.details[key]
  if type(detail) == "table" then
    detail.professions = entry.professions
    detail.lastProfessionUpdateAt = entry.lastUpdateAt
  end

  if MultiBot.ApplyBridgeBotProfession then
    MultiBot.ApplyBridgeBotProfession(entry.name, entry.professions)
  end

  debugPrint("ADDON:RX", "PROFESSION", entry.name)
  return entry
end

function Comm.ApplyBotProfessionsPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^|]+)") do
      if Comm.ApplyBotProfessionPayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "PROFESSIONS", tostring(applied))
  return applied
end

function Comm.ApplyBotDetailsPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^;]+)") do
      if Comm.ApplyBotDetailPayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "DETAILS", tostring(applied))
  return applied
end

local function parseStatsPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local level, rest2 = splitOnce(rest or "", "~")
  local gold, rest3 = splitOnce(rest2 or "", "~")
  local silver, rest4 = splitOnce(rest3 or "", "~")
  local copper, rest5 = splitOnce(rest4 or "", "~")
  local bagUsed, rest6 = splitOnce(rest5 or "", "~")
  local bagTotal, rest7 = splitOnce(rest6 or "", "~")
  local durabilityPct, rest8 = splitOnce(rest7 or "", "~")
  local xpPct, manaPct = splitOnce(rest8 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    level = tonumber(level or "0") or 0,
    gold = tonumber(gold or "0") or 0,
    silver = tonumber(silver or "0") or 0,
    copper = tonumber(copper or "0") or 0,
    bagUsed = tonumber(bagUsed or "0") or 0,
    bagTotal = tonumber(bagTotal or "0") or 0,
    durabilityPct = tonumber(durabilityPct or "0") or 0,
    xpPct = tonumber(xpPct or "0") or 0,
    manaPct = tonumber(manaPct or "0") or 0,
    lastUpdateAt = safeNow(),
  }
end

function Comm.ApplyStatsPayload(payload)
  local state = ensureBridgeState()
  local stats = parseStatsPayload(payload)
  if not stats then
    return nil
  end

  state.stats[string.lower(stats.name)] = stats

  if MultiBot.ApplyBridgeStats then
    MultiBot.ApplyBridgeStats(stats)
  end

  debugPrint(
    "ADDON:RX",
    "STATS",
    stats.name,
    tostring(stats.level or 0),
    tostring(stats.bagUsed or 0) .. "/" .. tostring(stats.bagTotal or 0),
    tostring(stats.durabilityPct or 0)
  )

  return stats
end

local function parsePvpStatsPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local arenaPoints, rest2 = splitOnce(rest or "", "~")
  local honorPoints, rest3 = splitOnce(rest2 or "", "~")
  local team2v2, rest4 = splitOnce(rest3 or "", "~")
  local rating2v2, rest5 = splitOnce(rest4 or "", "~")
  local team3v3, rest6 = splitOnce(rest5 or "", "~")
  local rating3v3, rest7 = splitOnce(rest6 or "", "~")
  local team5v5, rating5v5 = splitOnce(rest7 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    arenaPoints = tonumber(arenaPoints or "0") or 0,
    honorPoints = tonumber(honorPoints or "0") or 0,
    teams = {
      ["2v2"] = {
        team = urlDecodeField(team2v2),
        rating = tonumber(rating2v2 or "0") or 0,
      },
      ["3v3"] = {
        team = urlDecodeField(team3v3),
        rating = tonumber(rating3v3 or "0") or 0,
      },
      ["5v5"] = {
        team = urlDecodeField(team5v5),
        rating = tonumber(rating5v5 or "0") or 0,
      },
    },
    lastUpdateAt = safeNow(),
  }
end

function Comm.ApplyPvpStatsPayload(payload)
  local state = ensureBridgeState()
  local stats = parsePvpStatsPayload(payload)
  if not stats then
    return nil
  end

  state.pvpStats[string.lower(stats.name)] = stats

  if MultiBot.ApplyBridgePvpStats then
    MultiBot.ApplyBridgePvpStats(stats)
  end

  debugPrint(
    "ADDON:RX",
    "PVP_STATS",
    stats.name,
    tostring(stats.arenaPoints or 0),
    tostring(stats.honorPoints or 0)
  )

  return stats
end

local function ensureRuntimeTable(key)
  if MultiBot.Store and MultiBot.Store.EnsureRuntimeTable then
    return MultiBot.Store.EnsureRuntimeTable(key)
  end

  MultiBot[key] = type(MultiBot[key]) == "table" and MultiBot[key] or {}
  return MultiBot[key]
end

local function normalizeQuestMode(mode)
  mode = string.upper(trim(mode or "ALL"))
  if mode ~= "INCOMPLETED" and mode ~= "COMPLETED" and mode ~= "ALL" then
    mode = "ALL"
  end
  return mode
end

local function getActiveQuestRequest(token)
  local state = ensureBridgeState()
  token = trim(token)
  if token == "" then
    return nil
  end

  return state.questActive and state.questActive[token] or nil
end

local function buildQuestLink(questID, questName)
  questID = tonumber(questID or 0) or 0
  questName = tostring(questName or questID)
  return "|Hquest:" .. tostring(questID) .. ":0|h[" .. questName .. "]|h"
end

local function clearQuestStoresForMode(botName, mode)
  if type(botName) ~= "string" or botName == "" then
    return
  end

  mode = normalizeQuestMode(mode)

  if mode == "INCOMPLETED" or mode == "ALL" then
    ensureRuntimeTable("BotQuestsIncompleted")[botName] = {}
  end

  if mode == "COMPLETED" or mode == "ALL" then
    ensureRuntimeTable("BotQuestsCompleted")[botName] = {}
  end

  if mode == "ALL" then
    ensureRuntimeTable("BotQuestsAll")[botName] = {}
  end
end

function Comm.ApplyQuestBeginPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, mode = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)

  if botName == "" or not getActiveQuestRequest(token) then
    return false
  end

  clearQuestStoresForMode(botName, mode)
  debugPrint("ADDON:RX", "QUESTS_BEGIN", botName, mode)
  return true
end

function Comm.ApplyQuestItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local mode, rest3 = splitOnce(rest2 or "", "~")
  local status, rest4 = splitOnce(rest3 or "", "~")
  local questID, questName = splitOnce(rest4 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)
  status = string.upper(trim(status))
  questID = tonumber(questID or "0") or 0
  questName = trim(urlDecodeField(questName))
  if questName == "" then
    questName = tostring(questID)
  end

  if botName == "" or questID <= 0 or not getActiveQuestRequest(token) then
    return false
  end

  local incompletedStore = ensureRuntimeTable("BotQuestsIncompleted")
  local completedStore = ensureRuntimeTable("BotQuestsCompleted")
  local allStore = ensureRuntimeTable("BotQuestsAll")

  if status == "I" then
    incompletedStore[botName] = incompletedStore[botName] or {}
    incompletedStore[botName][questID] = questName
  elseif status == "C" then
    completedStore[botName] = completedStore[botName] or {}
    completedStore[botName][questID] = questName
  else
    return false
  end

  if mode == "ALL" then
    allStore[botName] = allStore[botName] or {}
    table.insert(allStore[botName], buildQuestLink(questID, questName))
  end

  debugPrint("ADDON:RX", "QUESTS_ITEM", botName, mode, status, tostring(questID))
  return true
end

function Comm.ApplyQuestEndPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, mode = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)

  if botName == "" or not getActiveQuestRequest(token) then
    return false
  end

  debugPrint("ADDON:RX", "QUESTS_END", botName, mode)
  return true
end

function Comm.ApplyQuestDonePayload(payload)
  local token, mode = splitOnce(payload or "", "~")
  token = trim(token)
  mode = normalizeQuestMode(mode)

  local state = ensureBridgeState()
  local request = getActiveQuestRequest(token)
  if not request then
    return false
  end

  state.questActive[token] = nil
  state.quests.lastMode = mode
  state.quests.lastDoneAt = safeNow()

  if MultiBot.OnBridgeQuestsDone then
    MultiBot.OnBridgeQuestsDone(mode, request)
  end

  debugPrint("ADDON:RX", "QUESTS_DONE", mode)
  return true
end

local function getActiveGameObjectRequest(token)
  local state = ensureBridgeState()
  token = trim(token)
  if token == "" then
    return nil
  end
  return state.gameObjectActive and state.gameObjectActive[token] or nil
end

function Comm.ApplyGameObjectBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  ensureRuntimeTable("LastGameObjectSearch")[botName] = {}
  debugPrint("ADDON:RX", "GAMEOBJECTS_BEGIN", botName)
  return true
end

function Comm.ApplyGameObjectItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, encodedLine = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  local store = ensureRuntimeTable("LastGameObjectSearch")
  store[botName] = store[botName] or {}
  table.insert(store[botName], urlDecodeField(encodedLine))
  return true
end

function Comm.ApplyGameObjectEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  debugPrint("ADDON:RX", "GAMEOBJECTS_END", botName)
  return true
end

function Comm.ApplyGameObjectDonePayload(payload)
  local token = trim(payload or "")
  local state = ensureBridgeState()
  local request = getActiveGameObjectRequest(token)
  if not request then
    return false
  end
  state.gameObjectActive[token] = nil
  state.gameObjects.lastDoneAt = safeNow()
  if MultiBot.OnBridgeGameObjectsDone then
    MultiBot.OnBridgeGameObjectsDone(request)
  end
  debugPrint("ADDON:RX", "GAMEOBJECTS_DONE")
  return true
end

local function getActiveTalentSpecRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.talentSpecActive
  if type(active) ~= "table" then
    return nil
  end

  if trim(token) ~= trim(active.token or "") then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

function Comm.ApplyTalentSpecBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.talentSpecs[string.lower(botName)] = {}

  if MultiBot.ApplyBridgeTalentSpecBegin then
    MultiBot.ApplyBridgeTalentSpecBegin(botName, token)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_BEGIN", botName)
  return true
end

function Comm.ApplyTalentSpecItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local index, rest3 = splitOnce(rest2 or "", "~")
  local specName, build = splitOnce(rest3 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  index = tonumber(index or "0") or 0
  specName = trim(urlDecodeField(specName))
  build = trim(build)

  if botName == "" or specName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local entry = {
    index = index,
    name = specName,
    build = build,
  }

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.talentSpecs[key] = state.talentSpecs[key] or {}
  table.insert(state.talentSpecs[key], entry)

  if MultiBot.ApplyBridgeTalentSpecItem then
    MultiBot.ApplyBridgeTalentSpecItem(botName, token, entry)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_ITEM", botName, specName, build)
  return true
end

local function getActiveGlyphRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.glyphActive
  if type(active) ~= "table" then
    return nil
  end

  if trim(token) ~= trim(active.token or "") then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function applyBridgeGlyphs(botName, token)
  local state = ensureBridgeState()
  local key = string.lower(botName)
  local glyphs = state.glyphs[key] or {}

  table.sort(glyphs, function(a, b)
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
  end)

  MultiBot.receivedGlyphs = MultiBot.receivedGlyphs or {}
  MultiBot.receivedGlyphs[botName] = glyphs

  if MultiBot.awaitGlyphs == botName then
    MultiBot.awaitGlyphs = nil
  end

  if MultiBot.ApplyBridgeGlyphs then
    MultiBot.ApplyBridgeGlyphs(botName, glyphs, token)
  elseif MultiBot.talent and MultiBot.talent.OnBridgeGlyphs then
    MultiBot.talent.OnBridgeGlyphs(botName, token, glyphs)
  elseif MultiBot.talent and MultiBot.talent.name == botName and MultiBot.FillDefaultGlyphs then
    MultiBot.FillDefaultGlyphs()
  end
end

local function getActiveOutfitRequest(botName, token)
  local active = ensureBridgeState().outfitActive
  if not active then return nil end
  botName = trim(botName)
  token = trim(token)
  if token ~= active.token then return nil end
  if botName ~= "" and string.lower(botName) ~= active.botNameKey then return nil end
  return active
end

local function clearActiveOutfitRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveOutfitRequest(botName, token) then
    state.outfitActive = nil
  end
end

function Comm.ApplyOutfitsBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveOutfitRequest(botName, token) then
    return false
  end

  local active = getActiveOutfitRequest(botName, token)
  if active then
    active.botName = botName
    active.botNameKey = string.lower(botName)
    active.lines = {}
  end

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeBegin then
    MultiBot.OutfitUI:HandleBridgeBegin(botName, token)
  end

  debugPrint("ADDON:RX", "OUTFITS_BEGIN", botName)
  return true
end

function Comm.ApplyOutfitsItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, encodedLine = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  local active = getActiveOutfitRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  local rawLine = urlDecodeField(encodedLine)
  active.lines[#active.lines + 1] = rawLine

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeLine then
    MultiBot.OutfitUI:HandleBridgeLine(botName, token, rawLine)
  end

  debugPrint("ADDON:RX", "OUTFITS_ITEM", botName, rawLine)
  return true
end

function Comm.ApplyOutfitsEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveOutfitRequest(botName, token) then
    return false
  end

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeEnd then
    MultiBot.OutfitUI:HandleBridgeEnd(botName, token)
  end

  clearActiveOutfitRequest(botName, token)
  debugPrint("ADDON:RX", "OUTFITS_END", botName)
  return true
end

function Comm.ApplyOutfitCommandPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, result = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  result = trim(result)

  local state = ensureBridgeState()
  local command = state.outfitCommands and state.outfitCommands[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.result = result

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeCommandResult then
    MultiBot.OutfitUI:HandleBridgeCommandResult(command.botName, token, result)
  end

  state.outfitCommands[token] = nil
  debugPrint("ADDON:RX", "OUTFITS_CMD", command.botName, result)
  return true
end

local function getActiveTrainerRequest(botName, token)
  local active = ensureBridgeState().trainerActive
  if not active then return nil end
  botName = trim(botName)
  token = trim(token)
  if token ~= active.token then return nil end
  if botName ~= "" and string.lower(botName) ~= active.botNameKey then return nil end
  return active
end

local function clearActiveTrainerRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveTrainerRequest(botName, token) then
    state.trainerActive = nil
  end
end

function Comm.ApplyTrainerBeginPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, trainerName = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  trainerName = trim(urlDecodeField(trainerName))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  active.botName = botName
  active.botNameKey = string.lower(botName)
  active.trainerEntry = trainerEntry
  active.trainerName = trainerName
  active.spells = {}

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeBegin then
    MultiBot.TrainerUI:HandleBridgeBegin(botName, token, trainerEntry, trainerName)
  end

  debugPrint("ADDON:RX", "TRAINER_BEGIN", botName, trainerEntry)
  return true
end

function Comm.ApplyTrainerItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local cost, canAfford = splitOnce(rest4 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  spellId = tonumber(spellId or "0") or 0
  cost = tonumber(cost or "0") or 0
  canAfford = tostring(canAfford or "0") == "1"

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active or spellId <= 0 then
    return false
  end

  local entry = {
    spellId = spellId,
    cost = cost,
    canAfford = canAfford,
    trainerEntry = trainerEntry,
  }
  active.spells[#active.spells + 1] = entry

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeLine then
    MultiBot.TrainerUI:HandleBridgeLine(botName, token, entry)
  end

  debugPrint("ADDON:RX", "TRAINER_ITEM", botName, spellId, cost, canAfford and 1 or 0)
  return true
end

function Comm.ApplyTrainerErrorPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, reason = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  reason = trim(urlDecodeField(reason))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  active.error = reason
  active.trainerEntry = trainerEntry

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeError then
    MultiBot.TrainerUI:HandleBridgeError(botName, token, reason, trainerEntry)
  end

  debugPrint("ADDON:RX", "TRAINER_ERROR", botName, reason)
  return true
end

function Comm.ApplyTrainerEndPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, trainerName = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  trainerName = trim(urlDecodeField(trainerName))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  local state = ensureBridgeState()
  state.trainerSpells[string.lower(botName)] = active.spells or {}

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeEnd then
    MultiBot.TrainerUI:HandleBridgeEnd(botName, token, trainerEntry, trainerName, active.spells or {}, active.error)
  end

  clearActiveTrainerRequest(botName, token)
  debugPrint("ADDON:RX", "TRAINER_END", botName)
  return true
end

function Comm.ApplyTrainerLearnPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local result, rest5 = splitOnce(rest4 or "", "~")
  local reason, rest6 = splitOnce(rest5 or "", "~")
  local learnedCount, spent = splitOnce(rest6 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  spellId = trim(urlDecodeField(spellId))
  result = trim(result)
  reason = trim(urlDecodeField(reason))
  learnedCount = tonumber(learnedCount or "0") or 0
  spent = tonumber(spent or "0") or 0

  local state = ensureBridgeState()
  local command = state.trainerCommands and state.trainerCommands[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.trainerEntry = trainerEntry
  command.spellId = spellId
  command.result = result
  command.reason = reason
  command.learnedCount = learnedCount
  command.spent = spent

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeLearnResult then
    MultiBot.TrainerUI:HandleBridgeLearnResult(command.botName, token, trainerEntry, spellId, result, reason, learnedCount, spent)
  end

  state.trainerCommands[token] = nil
  debugPrint("ADDON:RX", "TRAINER_LEARN", command.botName, spellId, result, reason)
  return true
end

function Comm.ApplyProfessionRecipeCraftPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local skillId, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local itemId, rest5 = splitOnce(rest4 or "", "~")
  local result, reason = splitOnce(rest5 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  skillId = tonumber(skillId or "0") or 0
  spellId = tonumber(spellId or "0") or 0
  itemId = tonumber(itemId or "0") or 0
  result = trim(result)
  reason = trim(urlDecodeField(reason))

  local state = ensureBridgeState()
  local command = state.professionRecipeCrafts and state.professionRecipeCrafts[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.skillId = skillId > 0 and skillId or command.skillId
  command.spellId = spellId > 0 and spellId or command.spellId
  command.itemId = itemId >= 0 and itemId or command.itemId
  command.result = result
  command.reason = reason

  if MultiBot.OnBridgeProfessionRecipeCraftResult then
    MultiBot.OnBridgeProfessionRecipeCraftResult(command.botName, command.skillId, command.spellId, command.itemId, result, reason, command)
  end

  state.professionRecipeCrafts[token] = nil
  debugPrint("ADDON:RX", "PROFESSION_RECIPE_CRAFT", command.botName, command.skillId, command.spellId, result, reason)
  return true
end

function Comm.ApplyGlyphsBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.glyphs[string.lower(botName)] = {}

  debugPrint("ADDON:RX", "GLYPHS_BEGIN", botName)
  return true
end

function Comm.ApplyGlyphsItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local index, rest3 = splitOnce(rest2 or "", "~")
  local itemId, rest4 = splitOnce(rest3 or "", "~")
  local glyphId, rest5 = splitOnce(rest4 or "", "~")
  local spellId, glyphType = splitOnce(rest5 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  local entry = {
    index = tonumber(index or "0") or 0,
    id = tonumber(itemId or "0") or 0,
    itemId = tonumber(itemId or "0") or 0,
    glyphId = tonumber(glyphId or "0") or 0,
    spellId = tonumber(spellId or "0") or 0,
    type = trim(urlDecodeField(glyphType or "")),
  }

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.glyphs[key] = state.glyphs[key] or {}
  table.insert(state.glyphs[key], entry)

  debugPrint("ADDON:RX", "GLYPHS_ITEM", botName, entry.index, entry.itemId, entry.glyphId, entry.spellId, entry.type)
  return true
end

function Comm.ApplyGlyphsPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, entries = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" then
    return false
  end

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.glyphs[key] = {}

  local fields = { strsplit("~", entries or "") }
  for i = 1, #fields do
    local raw = fields[i]
    if raw and raw ~= "" then
      local itemId, r1 = splitOnce(raw, ":")
      local glyphId, r2 = splitOnce(r1 or "", ":")
      local spellId, glyphType = splitOnce(r2 or "", ":")
      table.insert(state.glyphs[key], {
        index = #state.glyphs[key] + 1,
        id = tonumber(itemId or "0") or 0,
        itemId = tonumber(itemId or "0") or 0,
        glyphId = tonumber(glyphId or "0") or 0,
        spellId = tonumber(spellId or "0") or 0,
        type = trim(urlDecodeField(glyphType or "")),
      })
    end
  end

  applyBridgeGlyphs(botName, token)
  debugPrint("ADDON:RX", "GLYPHS", botName, #state.glyphs[key])
  return true
end

function Comm.ApplyGlyphsEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  applyBridgeGlyphs(botName, token)

  local state = ensureBridgeState()
  state.glyphActive = nil

  debugPrint("ADDON:RX", "GLYPHS_END", botName)
  return true
end

function Comm.ApplyTalentSpecEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.talentSpecActive = nil

  if MultiBot.ApplyBridgeTalentSpecEnd then
    MultiBot.ApplyBridgeTalentSpecEnd(botName, token)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_END", botName)
  return true
end

local function getActiveInventoryRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.inventoryActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveInventoryRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveInventoryRequest(botName, token) then
    state.inventoryActive = nil
  end
end

local function getActiveBankRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.bankActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(urlDecodeField(botName))) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveBankRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveBankRequest(botName, token) then
    state.bankActive = nil
  end
end

local function getActiveGuildBankRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.guildBankActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(urlDecodeField(botName))) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveGuildBankRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveGuildBankRequest(botName, token) then
    state.guildBankActive = nil
  end
end

local function getInventoryFrame()
  return MultiBot and MultiBot.inventory or nil
end

local function getActiveSpellbookRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.spellbookActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function clearActiveSpellbookRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveSpellbookRequest(botName, token) then
    state.spellbookActive = nil
  end
end

local function getSpellbookFrame()
  return MultiBot and MultiBot.spellbook or nil
end

local function getActiveBotSkillRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botSkillActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveBotReputationRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botReputationActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveBotEmblemRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botEmblemActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveProfessionRecipeRequest(botName, token, skillId)
  local state = ensureBridgeState()
  local active = state.professionRecipeActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  if skillId and tonumber(skillId or 0) ~= tonumber(active.skillId or 0) then
    return nil
  end

  return active
end

local function parseRecipeMaterials(raw)
  local materials = {}
  for token in string.gmatch(raw or "", "([^;]+)") do
    local itemId, rest = splitOnce(token, ":")
    local required, available = splitOnce(rest or "", ":")
    table.insert(materials, {
      itemId = tonumber(itemId or "0") or 0,
      required = tonumber(required or "0") or 0,
      available = tonumber(available or "0") or 0,
    })
  end
  return materials
end

function Comm.HandleAddonMessage(prefix, message, distribution, sender)
  if prefix ~= Comm.prefix then
    return false
  end

  local state = ensureBridgeState()
  local opcode, payload = splitOnce(message or "", "~")
  opcode = string.upper(trim(opcode))

  if opcode == "HELLO_ACK" then
    local protocol, serverName = splitOnce(payload, "~")
    local wasConnected = state.connected == true

    state.connected = true
    state.protocol = protocol ~= "" and protocol or nil
    state.server = serverName ~= "" and serverName or nil
    state.lastError = nil
    debugPrint("ADDON:RX", "HELLO_ACK", payload or "")

    if (not wasConnected or state.bootstrapPending) and state.protocol then
      safeDelay(0.10, function()
        if MultiBot and MultiBot.bridge and MultiBot.bridge.connected then
          state.bootstrapPending = false
          state.bootstrapDeadline = 0
          if Comm.RequestRoster then
            Comm.RequestRoster()
          end
          if Comm.RequestStates then
            Comm.RequestStates()
          end
          if Comm.RequestBotDetails then
            Comm.RequestBotDetails()
          end
        end
      end)
    else
      state.bootstrapPending = false
      state.bootstrapDeadline = 0
    end

    return true
  end

  if opcode == "PONG" then
    state.connected = true
    state.lastPongAt = safeNow()
    state.lastError = nil
    state.bootstrapPending = false
    state.bootstrapDeadline = 0
    debugPrint("ADDON:RX", "PONG", payload or "")
    return true
  end

  if opcode == "CAPS" then
    state.stateFramingCapable = false
    state.strategyMutationCapable = false
    for capability in string.gmatch(payload or "", "([^,]+)") do
      capability = trim(capability)
      if capability == STATE_FRAMING_CAPABILITY then
        state.stateFramingCapable = true
      elseif capability == STRATEGY_MUTATION_CAPABILITY then
        state.strategyMutationCapable = true
      end
    end
    debugPrint("ADDON:RX", "CAPS", payload or "")
    return true
  end

  if opcode == "WEAPON_ENCHANT" then
    state.connected = true

    local fields = splitFields(payload)
    if #fields ~= 9 then
      state.lastError = "WEAPON_ENCHANT_BAD_FIELD_COUNT"
      return true
    end

    local token = trim(fields[1])
    local botName = urlDecodeFieldStrict(fields[2], 64, false)
    local status = string.upper(trim(fields[3]))
    local mainItem = parseBoundedInteger(fields[4], 0, 4294967295)
    local mainEnchant = parseBoundedInteger(fields[5], 0, 4294967295)
    local mainDuration = parseBoundedInteger(fields[6], 0, 4294967295)
    local offItem = parseBoundedInteger(fields[7], 0, 4294967295)
    local offEnchant = parseBoundedInteger(fields[8], 0, 4294967295)
    local offDuration = parseBoundedInteger(fields[9], 0, 4294967295)

    if not isValidStateToken(token)
        or not botName
        or (status ~= "OK" and status ~= "RATE_LIMIT" and status ~= "BOT_NOT_VISIBLE" and status ~= "FORBIDDEN")
        or mainItem == nil
        or mainEnchant == nil
        or mainDuration == nil
        or offItem == nil
        or offEnchant == nil
        or offDuration == nil then
      state.lastError = "WEAPON_ENCHANT_BAD_PAYLOAD"
      return true
    end

    state.lastError = status == "OK" and nil or ("WEAPON_ENCHANT_" .. status)
    debugPrint("ADDON:RX", "WEAPON_ENCHANT", payload or "")

    if MultiBot.OnWeaponEnchantDebug then
      MultiBot.OnWeaponEnchantDebug({
        token = token,
        botName = botName,
        status = status,
        mainItem = mainItem,
        mainEnchant = mainEnchant,
        mainDuration = mainDuration,
        offItem = offItem,
        offEnchant = offEnchant,
        offDuration = offDuration,
      })
    end

    return true
  end

  if opcode == "ROSTER" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyRosterPayload(payload)
    return true
  end

  if opcode == "STATE_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStateBeginPayload(payload)
    return true
  end

  if opcode == "STATE_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStateItemPayload(payload)
    return true
  end

  if opcode == "STATE_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStateEndPayload(payload)
    return true
  end

  if opcode == "STATE_ABORT" then
    state.connected = true
    Comm.ApplyStateAbortPayload(payload)
    return true
  end

  if opcode == "STATES_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatesBeginPayload(payload)
    return true
  end

  if opcode == "STATES_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatesEndPayload(payload)
    return true
  end

  if opcode == "STATE" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatePayload(payload)
    return true
  end

  if opcode == "STATES" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatesPayload(payload)
    return true
  end

  if opcode == "DETAIL" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotDetailPayload(payload)
    return true
  end

  if opcode == "DETAILS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotDetailsPayload(payload)
    return true
  end

  if opcode == "PROFESSION" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotProfessionPayload(payload)
    return true
  end

  if opcode == "PROFESSIONS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotProfessionsPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecBeginPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecItemPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecEndPayload(payload)
    return true
  end

  if opcode == "OUTFITS_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsBeginPayload(payload)
  end

  if opcode == "OUTFITS_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsItemPayload(payload)
  end

  if opcode == "OUTFITS_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsEndPayload(payload)
  end

  if opcode == "OUTFITS_CMD" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitCommandPayload(payload)
  end

  if opcode == "TRAINER_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerBeginPayload(payload)
  end

  if opcode == "TRAINER_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerItemPayload(payload)
  end

  if opcode == "TRAINER_ERROR" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerErrorPayload(payload)
  end

  if opcode == "TRAINER_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerEndPayload(payload)
  end

  if opcode == "TRAINER_LEARN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerLearnPayload(payload)
  end

  if opcode == "GLYPHS_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsBeginPayload(payload)
    return true
  end

  if opcode == "GLYPHS_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsItemPayload(payload)
    return true
  end

  if opcode == "GLYPHS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsPayload(payload)
    return true
  end

  if opcode == "GLYPHS_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsEndPayload(payload)
    return true
  end

  if opcode == "QUESTS_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestBeginPayload(payload)
    return true
  end

  if opcode == "QUESTS_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestItemPayload(payload)
    return true
  end

  if opcode == "QUESTS_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestEndPayload(payload)
    return true
  end

  if opcode == "QUESTS_DONE" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestDonePayload(payload)
    return true
  end

  if opcode == "PVP_STATS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyPvpStatsPayload(payload)
    return true
  end

  if opcode == "STATS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatsPayload(payload)
    return true
  end

  if opcode == "GAMEOBJECTS_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectBeginPayload(payload)
  end

  if opcode == "GAMEOBJECTS_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectItemPayload(payload)
  end

  if opcode == "GAMEOBJECTS_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectEndPayload(payload)
  end

  if opcode == "GAMEOBJECTS_DONE" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectDonePayload(payload)
  end

  if opcode == "INV_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      if inventory and inventory.beginPayload then
        inventory:beginPayload(trim(botName))
      end
    end

    return true
  end

  if opcode == "INV_SUMMARY" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local gold, rest3 = splitOnce(rest2 or "", "~")
    local silver, rest4 = splitOnce(rest3 or "", "~")
    local copper, rest5 = splitOnce(rest4 or "", "~")
    local bagUsed, bagTotal = splitOnce(rest5 or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      if inventory and inventory.applySummaryData then
        inventory:applySummaryData({
          gold = tonumber(gold or "0") or 0,
          silver = tonumber(silver or "0") or 0,
          copper = tonumber(copper or "0") or 0,
          bagUsed = tonumber(bagUsed or "0") or 0,
          bagTotal = tonumber(bagTotal or "0") or 0,
        })
      end
    end

    return true
  end

  if opcode == "INV_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      local itemsFrame = inventory and inventory.frames and inventory.frames.Items or nil
      if itemsFrame and itemsFrame.addChatItem then
        itemsFrame:addChatItem(urlDecodeField(encodedLine))
        if itemsFrame.updateCanvas then
          itemsFrame:updateCanvas()
        end
      end
    end

    return true
  end

  if opcode == "INV_END" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      local itemsFrame = inventory and inventory.frames and inventory.frames.Items or nil
      if itemsFrame then
        if itemsFrame.updateCanvas then
          itemsFrame:updateCanvas()
        end
        if itemsFrame.updateLayout then
          itemsFrame:updateLayout()
        end
      end
    end

    clearActiveInventoryRequest(botName, token)
    return true
  end

  if opcode == "BANK_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      active.items = {}
      active.error = nil
      if MultiBot.OnBridgeBankBegin then
        MultiBot.OnBridgeBankBegin(botName, token)
      end
    end

    return true
  end

  if opcode == "BANK_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      table.insert(active.items, urlDecodeField(encodedLine))
    end

    return true
  end

  if opcode == "BANK_ERROR" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, reason = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    reason = trim(urlDecodeField(reason))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      active.error = reason ~= "" and reason or "FAILED"
    end

    return true
  end

  if opcode == "BANK_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.bankItems[key] = active.items or {}
      if MultiBot.OnBridgeBankItems then
        MultiBot.OnBridgeBankItems(botName, state.bankItems[key], active.error, token)
      end
    end

    clearActiveBankRequest(botName, token)
    return true
  end

  if opcode == "GBANK_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.items = {}
      active.error = nil
      if MultiBot.OnBridgeGuildBankBegin then
        MultiBot.OnBridgeGuildBankBegin(botName, token)
      end
    end

    return true
  end

  if opcode == "GBANK_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      table.insert(active.items, urlDecodeField(encodedLine))
    end

    return true
  end

  if opcode == "GBANK_ERROR" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, reason = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    reason = trim(urlDecodeField(reason))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.error = reason ~= "" and reason or "FAILED"
    end

    return true
  end

  if opcode == "GBANK_RIGHTS" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local canWithdraw, remaining = splitOnce(rest2 or "", "~")
    botName = trim(urlDecodeField(botName))
    canWithdraw = trim(canWithdraw)
    remaining = tonumber(remaining or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.rights = {
        canWithdraw = canWithdraw == "1" or string.lower(canWithdraw) == "true",
        remaining = remaining,
      }
    end

    return true
  end

  if opcode == "GBANK_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.guildBankItems[key] = active.items or {}
      if MultiBot.OnBridgeGuildBankItems then
        MultiBot.OnBridgeGuildBankItems(botName, state.guildBankItems[key], active.error, token, active.rights)
      end
    end

    clearActiveGuildBankRequest(botName, token)
    return true
  end

  if opcode == "INVENTORY_ITEM_ACTION" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local action, rest3 = splitOnce(rest2 or "", "~")
    local itemId, rest4 = splitOnce(rest3 or "", "~")
    local result, rest5 = splitOnce(rest4 or "", "~")
    local reason, moved = splitOnce(rest5 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    action = string.upper(trim(action))
    itemId = tonumber(itemId or "0") or 0
    result = trim(result)
    reason = trim(urlDecodeField(reason))
    moved = tonumber(moved or "0") or 0
    state.connected = true
    state.lastError = nil

    local command = state.inventoryItemActions and state.inventoryItemActions[token] or nil
    if command then
      command.botName = botName ~= "" and botName or command.botName
      command.action = action ~= "" and action or command.action
      command.itemId = itemId > 0 and itemId or command.itemId
      command.result = result
      command.reason = reason
      command.moved = moved

      if MultiBot.OnBridgeInventoryItemActionResult then
        MultiBot.OnBridgeInventoryItemActionResult(command.botName, command.action, command.itemId, result, reason, moved, command)
      end

      state.inventoryItemActions[token] = nil
    end

    debugPrint("ADDON:RX", "INVENTORY_ITEM_ACTION", botName, action, itemId, result, reason, moved)
    return true
  end

  if opcode == "SB_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.beginPayload then
        spellbook:beginPayload(trim(botName))
      elseif MultiBot and MultiBot.beginSpellbookCollection then
        MultiBot.beginSpellbookCollection(trim(botName))
      end
    end

    return true
  end

  if opcode == "SB_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, spellId = splitOnce(rest or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.appendSpellId then
        spellbook:appendSpellId(tonumber(spellId or "0") or 0, trim(botName))
      elseif MultiBot and MultiBot.addSpellById then
        MultiBot.addSpellById(tonumber(spellId or "0") or 0, trim(botName))
      end
    end

    return true
  end

  if opcode == "SB_END" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.finishPayload then
        spellbook:finishPayload()
      elseif MultiBot and MultiBot.finishSpellbookCollection then
        MultiBot.finishSpellbookCollection()
      end
    end

    clearActiveSpellbookRequest(botName, token)
    return true
  end

  if opcode == "BOT_SKILLS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      active.items = {}
    end

    return true
  end

  if opcode == "BOT_SKILLS_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local category, rest3 = splitOnce(rest2 or "", "~")
    local skillId, rest4 = splitOnce(rest3 or "", "~")
    local key, rest5 = splitOnce(rest4 or "", "~")
    local skillName, rest6 = splitOnce(rest5 or "", "~")
    local value, maxValue = splitOnce(rest6 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      table.insert(active.items, {
        category = trim(urlDecodeField(category)),
        skillId = tonumber(skillId or "0") or 0,
        key = trim(urlDecodeField(key)),
        name = trim(urlDecodeField(skillName)),
        value = tonumber(value or "0") or 0,
        max = tonumber(maxValue or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_SKILLS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botSkills[key] = active.items or {}
      if MultiBot.OnBridgeBotSkills then
        MultiBot.OnBridgeBotSkills(botName, state.botSkills[key], token)
      end
      state.botSkillActive = nil
    end

    return true
  end

  if opcode == "BOT_REPUTATIONS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      active.items = {}
    end

    return true
  end

  if opcode == "BOT_REPUTATION_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local factionId, rest3 = splitOnce(rest2 or "", "~")
    local factionName, rest4 = splitOnce(rest3 or "", "~")
    local rank, rest5 = splitOnce(rest4 or "", "~")
    local value, maxValue = splitOnce(rest5 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      table.insert(active.items, {
        factionId = tonumber(factionId or "0") or 0,
        name = trim(urlDecodeField(factionName)),
        rank = tonumber(rank or "0") or 0,
        value = tonumber(value or "0") or 0,
        max = tonumber(maxValue or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_REPUTATIONS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botReputations[key] = active.items or {}
      if MultiBot.OnBridgeBotReputations then
        MultiBot.OnBridgeBotReputations(botName, state.botReputations[key], token)
      end
      state.botReputationActive = nil
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      active.items = {}
      active.money = nil
    end

    return true
  end

  if opcode == "BOT_EMBLEM_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local itemId, count = splitOnce(rest2 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      table.insert(active.items, {
        itemId = tonumber(itemId or "0") or 0,
        count = tonumber(count or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_MONEY" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, money = splitOnce(rest or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      active.money = tonumber(money or "0") or 0
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botEmblems[key] = active.items or {}
      state.botEmblemMoney[key] = active.money
      if MultiBot.OnBridgeBotEmblems then
        MultiBot.OnBridgeBotEmblems(botName, state.botEmblems[key], token, state.botEmblemMoney[key])
      end
      state.botEmblemActive = nil
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_BEGIN" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, skillId = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      active.recipes = {}
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local skillId, rest3 = splitOnce(rest2 or "", "~")
    local spellId, rest4 = splitOnce(rest3 or "", "~")
    local itemId, rest5 = splitOnce(rest4 or "", "~")
    local difficulty, rest6 = splitOnce(rest5 or "", "~")
    local craftable, materials = splitOnce(rest6 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      table.insert(active.recipes, {
        skillId = skillId,
        spellId = tonumber(spellId or "0") or 0,
        itemId = tonumber(itemId or "0") or 0,
        difficulty = trim(urlDecodeField(difficulty)),
        craftable = tonumber(craftable or "0") or 0,
        materials = parseRecipeMaterials(urlDecodeField(materials)),
      })
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_END" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, skillId = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      local key = string.lower(botName) .. ":" .. tostring(skillId)
      state.professionRecipes[key] = active.recipes or {}
      if MultiBot.OnBridgeProfessionRecipes then
        MultiBot.OnBridgeProfessionRecipes(botName, skillId, state.professionRecipes[key], token)
      end
      state.professionRecipeActive = nil
    end

    return true
  end

  if opcode == "PROFESSION_RECIPE_CRAFT" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyProfessionRecipeCraftPayload(payload)
  end

  if opcode == "FORMATIONS_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyFormationsBeginPayload(payload)
  end

  if opcode == "FORMATIONS_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyFormationsItemPayload(payload)
  end

  if opcode == "FORMATIONS_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyFormationsEndPayload(payload)
  end

  if opcode == "GRAVEYARD_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "GRAVEYARD_ACK", payload or "")

    -- Wire shape: <graveyardId>~<token>~<result>
    local _, rest = splitOnce(payload or "", "~")
    local _, result = splitOnce(rest or "", "~")
    result = trim(result or "")

    -- A refusal is silent from the player's point of view -- they clicked and simply
    -- did not move -- so surface the reason rather than leaving them to guess whether
    -- the click registered at all.
    if result ~= "OK" and result ~= "" then
      local reasons = {
        IN_COMBAT = L("necronet.error.combat", "Necro-Network: cannot teleport while in combat."),
        IN_BATTLEGROUND = L("necronet.error.battleground", "Necro-Network: cannot teleport inside a battleground or arena."),
        NO_SUCH_GRAVEYARD = L("necronet.error.unknown", "Necro-Network: unknown graveyard."),
        BAD_COORDS = L("necronet.error.coords", "Necro-Network: that graveyard has invalid coordinates."),
      }
      systemMessage(reasons[result] or L("necronet.error.generic", "Necro-Network: teleport refused."))
    end

    return true
  end

  if opcode == "FORMATION_ACK" then
    local scope, rest = splitOnce(payload or "", "~")
    local target, rest2 = splitOnce(rest or "", "~")
    local token, rest3 = splitOnce(rest2 or "", "~")
    local successText, rest4 = splitOnce(rest3 or "", "~")
    local failureText, encodedFormation = splitOnce(rest4 or "", "~")

    scope = string.upper(trim(scope))
    target = trim(urlDecodeField(target))
    token = trim(token)
    local success = tonumber(successText or "0") or 0
    local failure = tonumber(failureText or "0") or 0
    local formation = string.lower(trim(urlDecodeField(encodedFormation)))

    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "FORMATION_ACK", payload or "")

    local pending = state.formationCommands[token]
    state.formationCommands[token] = nil

    local result = {
      scope = scope,
      target = target,
      token = token,
      success = success,
      failure = failure,
      formation = formation,
    }

    if pending and type(pending.callback) == "function" then
      pending.callback(result)
    end

    if MultiBot.OnFormationCommandApplied then
      MultiBot.OnFormationCommandApplied(result)
    end

    if success <= 0 then
      systemMessage(L("formation.confirm.none"))
    elseif failure > 0 then
      systemMessage(string.format(
        L("formation.confirm.partial"),
        success,
        failure
      ))
    end

    return true
  end

  if opcode == "STRATEGY_ACK" then
    local fields = splitFields(payload or "")
    if #fields ~= 8 then
      state.lastError = "STRATEGY_ACK_BAD_FIELD_COUNT"
      return true
    end

    local scope = string.upper(trim(fields[1]))
    local target = urlDecodeFieldStrict(fields[2], 64, true)
    local token = trim(fields[3])
    local stateScope = string.upper(trim(fields[4]))
    local matched = parseBoundedInteger(fields[5], 0, 128)
    local succeeded = parseBoundedInteger(fields[6], 0, 128)
    local failed = parseBoundedInteger(fields[7], 0, 128)
    local reason = urlDecodeFieldStrict(fields[8], 64, false)

    local pending = state.strategyMutationCommands[token]
    if (scope ~= "ALL" and scope ~= "GROUP" and scope ~= "PARTY" and scope ~= "RAID" and scope ~= "BOT")
        or target == nil
        or not isValidStateToken(token)
        or (stateScope ~= "C" and stateScope ~= "N")
        or matched == nil
        or succeeded == nil
        or failed == nil
        or reason == nil
        or succeeded + failed > matched
        or type(pending) ~= "table"
        or pending.scope ~= scope
        or string.lower(pending.target or "") ~= string.lower(target)
        or pending.stateScope ~= stateScope then
      state.lastError = "STRATEGY_ACK_INVALID"
      return true
    end

    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "STRATEGY_ACK", payload or "")

    local status = "failed"
    if matched == 0 then
      status = "no_match"
    elseif succeeded == matched and failed == 0 then
      status = "ok"
    elseif succeeded > 0 then
      status = "partial"
    end

    finishStrategyMutationCommand(token, {
      status = status,
      scope = scope,
      target = target,
      stateScope = stateScope,
      matched = matched,
      succeeded = succeeded,
      failed = failed,
      reason = reason,
    })
    return true
  end

  if opcode == "RTI_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "RTI_ACK", payload or "")
    return true
  end

  if opcode == "COMBAT_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "COMBAT_ACK", payload or "")
    return true
  end

  if opcode == "POSITION_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "POSITION_ACK", payload or "")

    local rest = select(2, splitOnce(payload or "", "~"))
    local rest2 = select(2, splitOnce(rest, "~"))
    local rest3 = select(2, splitOnce(rest2, "~"))
    local executedText, encodedCommand = splitOnce(rest3, "~")
    local executed = tonumber(executedText) or 0
    local command = trim(urlDecodeField(encodedCommand))

    if executed > 0 then
      local distance = string.match(command, "^disperse set%s+(.+)$")

      if distance then
        systemMessage(string.format(
          L("disperse.confirm.set", "Disperse set to %s yards."),
          distance
        ))
      elseif command == "disperse disable" then
        systemMessage(L("disperse.confirm.disable", "Disperse disabled."))
      end
    end

    return true
  end

  if opcode == "LOOT_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "LOOT_ACK", payload or "")

    local rest = select(2, splitOnce(payload or "", "~"))
    local rest2 = select(2, splitOnce(rest, "~"))
    local rest3 = select(2, splitOnce(rest2, "~"))
    local executedText, encodedCommand = splitOnce(rest3, "~")
    local executed = tonumber(executedText) or 0
    local command = string.lower(trim(urlDecodeField(encodedCommand)))

    if executed <= 0 then
      systemMessage(L("loot.confirm.none", "Loot command was not applied to any bot."))
      return true
    end

    if MultiBot.OnLootCommandApplied then
      MultiBot.OnLootCommandApplied(command, executed)
    end

    if command == "nc +loot" then
      systemMessage(string.format(L("loot.confirm.enable", "Loot enabled for %d bot(s)."), executed))
      return true
    end

    if command == "nc -loot" then
      systemMessage(string.format(L("loot.confirm.disable", "Loot disabled for %d bot(s)."), executed))
      return true
    end

    local profile = command:match("^ll%s+([%w_%-]+)$")
    if profile then
      local profileName = ({
        all = L("loot.profile.all", "All"),
        normal = L("loot.profile.normal", "Normal"),
        gray = L("loot.profile.gray", "Gray"),
        quest = L("loot.profile.quest", "Quest"),
        skill = L("loot.profile.skill", "Skill"),
      })[profile] or profile

      systemMessage(string.format(L("loot.confirm.profile", "Loot profile set to %s for %d bot(s)."), profileName, executed))
    end

    return true
  end

  if opcode == "ERR" then
    state.lastError = payload
    debugPrint("ADDON:RX", "ERR", payload or "")

    local fields = splitFields(payload or "")
    if #fields == 4 then
      local requestType = urlDecodeFieldStrict(fields[2], 32, false)
      local token = trim(fields[3])
      local reason = urlDecodeFieldStrict(fields[4], 64, false)

      requestType = requestType and string.upper(trim(requestType)) or nil
      if requestType and isValidStateToken(token) and reason then
        if requestType == "STRATEGY" and state.strategyMutationCommands[token] then
          finishStrategyMutationCommand(token, {
            status = "error",
            matched = 0,
            succeeded = 0,
            failed = 0,
            reason = reason,
          })
        elseif (requestType == "STATE" or requestType == "STATES") and state.stateRequests[token] then
          clearStateRequest(state, token)
        end
      end
    end

    return true
  end

  debugPrint("ADDON:RX", opcode, payload or "")
  return true
end

local function dispatchBootstrapRequests()
  Comm.SendHello()
  Comm.SendPing()
  Comm.RequestRoster()
  if Comm.RequestStates then
    Comm.RequestStates()
  end
  if Comm.RequestBotDetails then
    Comm.RequestBotDetails()
  end
end

function Comm.OnPlayerEnteringWorld()
  local state = ensureBridgeState()
  state.states = {}
  state.stateRequests = {}
  state.stateActive = {}
  state.stateLatestByBot = {}
  state.stateLatestOrderByBot = {}
  state.stateGlobalLatestToken = nil
  state.stateFramingCapable = false
  state.strategyMutationCapable = false
  state.strategyMutationCommands = {}
  state.details = {}
  state.stats = {}
  state.pvpStats = {}
  state.quests = {}
  state.questActive = {}
  state.gameObjects = {}
  state.gameObjectActive = {}
  state.formationCommands = {}
  state.formationQueryActive = nil
  state.talentSpecs = {}
  state.talentSpecActive = nil
  state.inventoryActive = nil
  state.spellbookActive = nil
  state.botSkills = {}
  state.botSkillActive = nil
  state.botReputations = {}
  state.botReputationActive = nil
  state.botEmblems = {}
  state.botEmblemMoney = {}
  state.botEmblemActive = nil
  state.professionRecipes = {}
  state.professionRecipeActive = nil
  state.professionRecipeCrafts = {}
  state.outfitActive = nil
  state.outfitCommands = {}
  state.trainerActive = nil
  state.trainerCommands = {}
  state.trainerSpells = {}
  Comm.MarkDisconnected(nil)
  state.trainerActive = nil
  state.trainerCommands = {}
  state.trainerSpells = {}
  state.bootstrapPending = true
  state.bootstrapDeadline = safeNow() + 4.0

  local function expireBootstrap()
    local bridge = ensureBridgeState()
    if not bridge.connected and bridge.bootstrapPending and bridge.bootstrapDeadline > 0 and safeNow() >= bridge.bootstrapDeadline then
      bridge.bootstrapPending = false
      bridge.bootstrapDeadline = 0
    end
  end

  if not MultiBot.TimerAfter then
    dispatchBootstrapRequests()
    expireBootstrap()
    return
  end

  dispatchBootstrapRequests()

  MultiBot.TimerAfter(1.0, function()
    dispatchBootstrapRequests()
  end)

  MultiBot.TimerAfter(4.1, expireBootstrap)
end

ensureBridgeState()