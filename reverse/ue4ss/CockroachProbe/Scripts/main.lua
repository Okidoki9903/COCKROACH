-- CockroachProbe — UE4SS mod d'instrumentation runtime pour "Les Fourmis" (Empire of the Ants, UE 5.4).
-- Objectif : mesurer caméra + mouvement multi-surfaces (Bible §4, phases 2-4).
-- Ne lit que des valeurs en mémoire pendant le jeu ; n'extrait aucun asset ni code.
--
-- Classes du jeu (trouvées par dump, module /Script/Empire) :
--   Pawn joueur      BP_PlayerPawn_C <- APlayerPawn <- APawn
--   Mouvement        PlayerPawn.MovementController : UPlayerMovementController (UPawnMovementComponent custom)
--                    paramètres dans MovementController.MovementData : UPlayerMovementData (DataAsset)
--   Caméra           PlayerPawn.CameraController : UPlayerCameraController (USceneComponent custom, "leash")
--                    PlayerPawn.CameraComponent : UCineCameraComponent ; PlayerPawn.CameraAttachComponent (pivot)
--
-- Touches :
--   F6  démarrer / arrêter l'enregistrement CSV (frames)
--   F7  snapshot des paramètres (caméra, mouvement, cine camera…) -> params_*.txt
--   F8  marqueur d'événement dans le CSV (ex : "début montée mur") — incrémente le compteur
--   F9  inspection : classes + propriétés du pawn et des objets liés -> inspect_*.txt
--   F10 perception : réglages de détection (niveau, clans, tables, faune) + unités proches -> perception_*.txt
--   (F6 écrit aussi units_*.csv : unités à moins de 5000 u, état, portée de détection, cible poursuivie)
--
-- Sorties : dossier <Win64>/ue4ss/Mods/CockroachProbe/out/ (créé par install_probe.ps1)

-- Le dossier de travail du jeu est Binaries/Win64, pas le dossier du mod : on déduit
-- le chemin absolu de out/ depuis l'emplacement de ce script (…/CockroachProbe/Scripts/main.lua).
local function modDir()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("\\", "/")
    local dir = src:match("^(.*)/Scripts/[^/]+$")
    return dir or "ue4ss/Mods/CockroachProbe"
end
local OUT_DIR = modDir() .. "/out/"
-- Échantillonnage : une fois par image, dans le fil du jeu (LoopInGameThreadAfterFrames).
-- L'ancienne version (LoopAsync + ExecuteInGameThread à 60 Hz) faisait planter le jeu.

local recording = false
local stopRequested = false
local csv = nil
local marker = 0
local t0 = os.clock()

local function try(fn, default)
    local s, v = pcall(fn)
    if s and v ~= nil then return v end
    return default
end

-- Certains objets renvoyés par UE4SS n'ont pas de méthode IsValid : on protège l'appel.
local function ok(o)
    if o == nil or type(o) ~= "userdata" then return false end
    return try(function() return o:IsValid() end, false)
end

local function fullName(o)
    return ok(o) and try(function() return o:GetFullName() end, "?") or "None"
end

local function vec(v)
    if v == nil then return "nan,nan,nan" end
    return try(function() return string.format("%.4f,%.4f,%.4f", v.X, v.Y, v.Z) end, "nan,nan,nan")
end

local function rot(r)
    if r == nil then return "nan,nan,nan" end
    return try(function() return string.format("%.4f,%.4f,%.4f", r.Pitch, r.Yaw, r.Roll) end, "nan,nan,nan")
end

local function num(v, fmtStr)
    if type(v) == "boolean" then return v and "1" or "0" end
    if type(v) ~= "number" then return "nan" end
    return string.format(fmtStr or "%.4f", v)
end

local function getPC()
    local pc = FindFirstOf("PlayerController")
    if ok(pc) then return pc end
    return nil
end

local function getPawn(pc)
    local p = try(function() return pc.Pawn end)
    if ok(p) then return p end
    p = try(function() return pc.AcknowledgedPawn end)
    if ok(p) then return p end
    return nil
end

-- Objets liés au joueur, mis en cache (on ne recherche que si le pawn change).
local cache = { pawnName = nil }

local function refreshCache(pc, pawn)
    local n = fullName(pawn)
    if cache.pawnName == n and ok(cache.cm) then return end
    cache.pawnName = n
    cache.cm = try(function() return pc.PlayerCameraManager end)
    cache.move = try(function() return pawn.MovementController end)
    cache.moveData = ok(cache.move) and try(function() return cache.move.MovementData end) or nil
    cache.camCtrl = try(function() return pawn.CameraController end)
    cache.cine = try(function() return pawn.CameraComponent end)
    cache.attach = try(function() return pawn.CameraAttachComponent end)
    cache.world = try(function() return pawn:GetWorld() end)
    cache.gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
end

local function gameTime()
    if not ok(cache.gs) or not ok(cache.world) then return nil end
    return try(function() return cache.gs:GetTimeSeconds(cache.world) end)
end

local function compLoc(c)
    return ok(c) and try(function() return c:K2_GetComponentLocation() end) or nil
end

local function compRot(c)
    return ok(c) and try(function() return c:K2_GetComponentRotation() end) or nil
end

local HEADER = table.concat({
    "t", "game_t", "marker",
    "pawn_x,pawn_y,pawn_z",
    "pawn_pitch,pawn_yaw,pawn_roll",
    "pawn_fwd_x,pawn_fwd_y,pawn_fwd_z",
    "pawn_right_x,pawn_right_y,pawn_right_z",
    "pawn_up_x,pawn_up_y,pawn_up_z",
    "vel_x,vel_y,vel_z",
    "fvel_x,fvel_y,fvel_z",
    "cam_x,cam_y,cam_z",
    "cam_pitch,cam_yaw,cam_roll",
    "cam_fwd_x,cam_fwd_y,cam_fwd_z",
    "cam_up_x,cam_up_y,cam_up_z",
    "fov",
    "ctrl_pitch,ctrl_yaw,ctrl_roll",
    "camctrl_x,camctrl_y,camctrl_z",
    "camctrl_pitch,camctrl_yaw,camctrl_roll",
    "pivot_x,pivot_y,pivot_z",
    "cine_x,cine_y,cine_z",
    "focal",
    "move_mode", "running", "in_air",
    "damaged", "dying",
}, ",")

local function sample()
    local pc = ok(cache.pc) and cache.pc or getPC()
    if pc == nil then return end
    cache.pc = pc
    local pawn = getPawn(pc)
    if pawn == nil then return end
    refreshCache(pc, pawn)
    local cm, move, cine = cache.cm, cache.move, cache.cine

    local line = table.concat({
        string.format("%.4f", os.clock() - t0),
        num(gameTime()),
        tostring(marker),
        vec(try(function() return pawn:K2_GetActorLocation() end)),
        rot(try(function() return pawn:K2_GetActorRotation() end)),
        vec(try(function() return pawn:GetActorForwardVector() end)),
        vec(try(function() return pawn:GetActorRightVector() end)),
        vec(try(function() return pawn:GetActorUpVector() end)),
        vec(try(function() return pawn:GetVelocity() end)),
        vec(ok(move) and try(function() return move:GetFrameVelocity() end) or nil),
        vec(ok(cm) and try(function() return cm:GetCameraLocation() end) or nil),
        rot(ok(cm) and try(function() return cm:GetCameraRotation() end) or nil),
        vec(ok(cine) and try(function() return cine:GetForwardVector() end) or nil),
        vec(ok(cine) and try(function() return cine:GetUpVector() end) or nil),
        num(ok(cm) and try(function() return cm:GetFOVAngle() end) or nil, "%.3f"),
        rot(try(function() return pc:GetControlRotation() end)),
        vec(compLoc(cache.camCtrl)),
        rot(compRot(cache.camCtrl)),
        vec(compLoc(cache.attach)),
        vec(compLoc(cine)),
        num(ok(cine) and try(function() return cine.CurrentFocalLength end) or nil, "%.3f"),
        num(ok(move) and try(function() return move:GetMode() end) or nil, "%d"),
        num(ok(move) and try(function() return move:IsRunning() end) or nil),
        num(ok(move) and try(function() return move:IsInAir() end) or nil),
        num(try(function() return pawn:IsReceivingDamages() end)),
        num(try(function() return pawn:IsDying() end)),
    }, ",")
    csv:write(line, "\n")
end

local loopHandle = nil
local ucsv = nil         -- unités proches (perception), ~10 Hz
local frameCount = 0
local UNIT_EVERY = 6     -- images entre deux relevés d'unités
local UNIT_RADIUS = 5000 -- u autour du joueur
local UHEADER = "game_t,marker,id,type,category,clan,state,substate,transition,x,y,z,dist,"
    .. "detection_range,fight_radius,chased_unit,chased_general,moving,agents,health,max_health,vagabond,player_x,player_y,player_z"

local function getGameState()
    if ok(cache.gameState) then return cache.gameState end
    cache.gameState = FindFirstOf("EmpireGameState")
    return cache.gameState
end

local function sampleUnits()
    local gs = getGameState()
    if not ok(gs) or ucsv == nil then return end
    local pc = cache.pc
    local pawn = pc and getPawn(pc) or nil
    if pawn == nil then return end
    local pl = try(function() return pawn:K2_GetActorLocation() end)
    if pl == nil then return end
    local px, py, pz = pl.X, pl.Y, pl.Z
    local gt = num(gameTime())
    local arr = try(function() return gs.m_unitsPrivate end)
    if arr == nil then return end
    arr:ForEach(function(_, elem)
        pcall(function()
            local u = elem:get()
            local tr = u.m_transform.Translation
            local dx, dy, dz = tr.X - px, tr.Y - py, tr.Z - pz
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist > UNIT_RADIUS then return end
            ucsv:write(table.concat({
                gt, tostring(marker), num(u.m_id, "%d"), num(u.m_type, "%d"), num(u.m_category, "%d"),
                num(u.m_clan, "%d"), num(u.m_behaviourState, "%d"), num(u.m_behaviourSubstate, "%d"),
                num(u.m_behaviourTransition, "%d"),
                string.format("%.2f,%.2f,%.2f", tr.X, tr.Y, tr.Z), string.format("%.2f", dist),
                num(u.m_detectionRange, "%.2f"), num(u.m_fightRadius, "%.2f"), num(u.m_chasedUnitId, "%d"),
                num(u.m_chasedGeneral, "%d"), num(u.m_isMoving), num(u.m_agentCount, "%d"),
                num(u.m_healthPoints, "%.1f"), num(u.m_maxHealthPoints, "%.1f"), num(u.m_isVagabond),
                string.format("%.2f,%.2f,%.2f", px, py, pz),
            }, ","), "\n")
        end)
    end)
end
local recGen = 0 -- numéro d'enregistrement : une vieille boucle survivante ne doit rien faire

local function closeCsv()
    local wasOpen = csv ~= nil
    if csv ~= nil then csv:close() csv = nil end
    if ucsv ~= nil then ucsv:close() ucsv = nil end
    recording = false
    stopRequested = false
    -- Dans cette version d'UE4SS, "return true" n'arrête pas la boucle : on l'annule par son handle.
    if loopHandle ~= nil then
        pcall(CancelDelayedAction, loopHandle)
        loopHandle = nil
    end
    if wasOpen then print("[CockroachProbe] STOP" .. string.char(10)) end
end

local function startRecording()
    if recording then return end
    local name = OUT_DIR .. "frames_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    csv = io.open(name, "w")
    if csv == nil then
        print("[CockroachProbe] impossible d'ouvrir " .. name .. " (créer le dossier out/)\n")
        return
    end
    csv:write(HEADER, "\n")
    ucsv = io.open((name:gsub("frames_", "units_")), "w")
    if ucsv ~= nil then ucsv:write(UHEADER, "\n") end
    frameCount = 0
    t0 = os.clock()
    marker = 0
    stopRequested = false
    recording = true
    print("[CockroachProbe] REC -> " .. name .. "\n")
    -- Tout (écriture et fermeture du fichier) se fait dans le fil du jeu.
    recGen = recGen + 1
    local myGen = recGen
    loopHandle = LoopInGameThreadAfterFrames(1, function()
        if myGen ~= recGen then return true end
        if stopRequested or not recording then
            closeCsv()
            return true -- true = arrêter la boucle
        end
        local s, e = pcall(sample)
        if not s then print("[CockroachProbe] sample erreur: " .. tostring(e) .. "\n") end
        frameCount = frameCount + 1
        if frameCount % UNIT_EVERY == 0 then
            local s2, e2 = pcall(sampleUnits)
            if not s2 then print("[CockroachProbe] units erreur: " .. tostring(e2) .. "\n") end
        end
        return false
    end)
end

local function stopRecording()
    stopRequested = true -- la boucle du fil du jeu fermera le fichier
end

local function fmt(v)
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return tostring(v) end
    if t == "userdata" then
        local s = try(function()
            if v.X ~= nil then return string.format("(%.4f, %.4f, %.4f)", v.X, v.Y, v.Z) end
        end)
        if s then return s end
        s = try(function()
            if v.Pitch ~= nil then return string.format("(P=%.4f, Y=%.4f, R=%.4f)", v.Pitch, v.Yaw, v.Roll) end
        end)
        if s then return s end
        s = try(function() return v:ToString() end)
        if s then return s end
    end
    return "<" .. t .. ">"
end

-- Propriétés par réflexion : on remonte la chaîne de classes jusqu'aux classes de base
-- sans intérêt et on écrit nom, type, valeur pour les types simples.
local STOP_AT = { Object = true, Actor = true, ActorComponent = true, SceneComponent = true,
                  DataAsset = true, PrimaryDataAsset = true }

local function classChain(o)
    local names = {}
    local c = try(function() return o:GetClass() end)
    while ok(c) do
        names[#names + 1] = fullName(c)
        c = try(function() return c:GetSuperStruct() end)
    end
    return table.concat(names, "\n#   <- ")
end

local function dumpProps(f, o, full)
    local c = try(function() return o:GetClass() end)
    while ok(c) do
        local cname = try(function() return c:GetFName():ToString() end, "?")
        if not full and STOP_AT[cname] then break end
        pcall(function()
            c:ForEachProperty(function(prop)
                local pname = prop:GetFName():ToString()
                local ptype = try(function() return prop:GetClass():GetFName():ToString() end, "?")
                local val = ""
                if ptype:match("Object") then
                    val = fullName(try(function() return o[pname] end))
                elseif ptype:match("Float") or ptype:match("Double") or ptype:match("Int") or ptype:match("Bool")
                    or ptype:match("Byte") or ptype:match("Enum") or ptype:match("Struct") or ptype:match("Name") then
                    val = fmt(try(function() return o[pname] end))
                end
                f:write(string.format("  %-26s %-40s %-18s = %s\n", cname, pname, ptype, val))
            end)
        end)
        c = try(function() return c:GetSuperStruct() end)
    end
end

local function dumpObj(f, label, o, full)
    f:write("\n==== ", label, " : ", fullName(o), "\n")
    if not ok(o) then return end
    f:write("# ", classChain(o), "\n")
    dumpProps(f, o, full)
end

-- F7 : paramètres de réglage (ce qu'il faut pour la spec).
local function snapshot()
    local pc = getPC()
    local pawn = pc and getPawn(pc) or nil
    if pawn == nil then print("[CockroachProbe] pas de pawn\n") return end
    refreshCache(pc, pawn)
    local name = OUT_DIR .. "params_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(name, "w")
    if f == nil then return end
    f:write("# Pawn: ", fullName(pawn), "\n")
    f:write("# game_t: ", num(gameTime()), "\n")
    f:write("# ActorScale3D: ", vec(try(function() return pawn:GetActorScale3D() end)), "\n")
    dumpObj(f, "PlayerCameraController", cache.camCtrl)
    dumpObj(f, "PlayerMovementController", cache.move)
    dumpObj(f, "PlayerMovementData", cache.moveData, true)
    dumpObj(f, "CineCameraComponent", cache.cine)
    dumpObj(f, "PlayerCameraManager", cache.cm)
    f:close()
    print("[CockroachProbe] snapshot -> " .. name .. "\n")
end

-- F9 : inspection large (controller, camera manager, pawn).
local function inspect()
    local pc = getPC()
    local pawn = pc and getPawn(pc) or nil
    local name = OUT_DIR .. "inspect_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(name, "w")
    if f == nil then
        print("[CockroachProbe] impossible d'ouvrir " .. name .. "\n")
        return
    end
    dumpObj(f, "PlayerController", pc)
    dumpObj(f, "PlayerCameraManager", pc and try(function() return pc.PlayerCameraManager end) or nil)
    dumpObj(f, "Pawn", pawn)
    f:close()
    print("[CockroachProbe] inspect -> " .. name .. "\n")
end

-- F10 : réglages de perception (niveau, clans, tables de données, faune, unités proches).
local function writeFields(f, prefix, obj, fields)
    local parts = {}
    for _, k in ipairs(fields) do
        local v = try(function() return obj[k] end)
        if type(v) == "userdata" then v = try(function() return v:ToString() end, fmt(v)) end
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    f:write(prefix, table.concat(parts, "  "), "\n")
end

local CORESTAT_FIELDS = { "DetectionRange", "PlayerDetectionRange", "CreepsDetectionRangeFactor", "StandardUnitSpeed",
    "StandardCohesionRadius", "UnitBreakFightDuration", "IdleHealSpeed", "HostileUnitDamagesPerSec", "CreepDamagesPerSec",
    "CreepRedZoneRatio", "CreepYellowZoneRatio", "AttritionTimeToKill" }
local UNITSTAT_FIELDS = { "TypeUnit", "UnitName", "Category", "Tier", "IsAntUnit", "Movement", "MaxAgents", "Moral",
    "Cohesion", "AggroRadiusFactor", "MeleeSlotsNumber", "BreakFightDurationFactor" }
local CLAN_FIELDS = { "Clan", "Alliance", "Civilization", "PlayerType", "DetectionTime", "DetectionRangeModifier",
    "Personality", "ThinkSpeed", "Wisdom", "ArmyCount", "StartEnabled" }

local function perception()
    local name = OUT_DIR .. "perception_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(name, "w")
    if f == nil then return end
    f:write("# game_t: ", num(gameTime()), "\n")

    local lvl = FindFirstOf("SimulatedLevel")
    f:write("\n==== Niveau : ", fullName(lvl), "\n")
    if ok(lvl) then
        writeFields(f, "  ", lvl, { "ColdDetectionDistance", "TepidDetectionDistance", "WarmDetectionDistance",
            "SizzlingDetectionDistance", "HotDetectionDistance" })
        local clans = try(function() return lvl.ClansSetup end)
        if clans ~= nil then
            clans:ForEach(function(i, elem)
                pcall(function() writeFields(f, "  clan[" .. i .. "] ", elem:get(), CLAN_FIELDS) end)
            end)
        end
    end

    local dts = FindAllOf("DataTable") or {}
    for _, dt in ipairs(dts) do
        if ok(dt) then
            local rs = try(function() return dt.RowStruct:GetFName():ToString() end, "?")
            local fields = (rs == "CoreStat" and CORESTAT_FIELDS) or (rs == "UnitStats" and UNITSTAT_FIELDS) or nil
            if fields ~= nil then
                f:write("\n==== DataTable ", fullName(dt), " (", rs, ")\n")
                local okRows = pcall(function()
                    dt:ForEachRow(function(rowName, row)
                        local rn = try(function() return rowName:ToString() end, tostring(rowName))
                        writeFields(f, "  [" .. rn .. "] ", row, fields)
                    end)
                end)
                if not okRows then f:write("  (ForEachRow indisponible)\n") end
            end
        end
    end

    local function dumpAll(cls, fields)
        local all = FindAllOf(cls) or {}
        f:write("\n==== ", cls, " (", #all, ")\n")
        for i, o in ipairs(all) do
            if ok(o) and i <= 40 then
                local loc = try(function() return o:K2_GetActorLocation() end)
                writeFields(f, "  " .. vec(loc) .. "  ", o, fields)
            end
        end
    end
    dumpAll("JumpingSpiderWaypoint", { "PlayerFleeRange", "PlayerAlertRange" })
    dumpAll("JumpingSpider", { "JumpSpeed", "BaseJumpHeight", "JumpRotationSpeed", "AlertRotationSpeed" })
    dumpAll("BreathingWorldFollowerSpawner", { "PlayerHearingRange", "AgentSpeed", "AmountToSpawn", "DivergenceFactor" })
    dumpAll("BreathingWorldSecurityLine", { "AgentsDistance", "BlockerForwardDist", "BlockerBoundaryDist" })

    local pc = getPC()
    local pawn = pc and getPawn(pc) or nil
    if pawn ~= nil then
        f:write("\n==== Joueur\n")
        writeFields(f, "  ", pawn, { "NestDetectionSphereRadius", "ResourceDetectionSphereRadius",
            "ForagingDetectionSphereRadius", "SpideySenseTickInterval", "SpideySenseTickNumber", "BarrierInteractionRadius" })
    end

    -- Résumé des unités proches : état et portée de détection.
    local gs = getGameState()
    if ok(gs) and pawn ~= nil then
        local pl = pawn:K2_GetActorLocation()
        f:write("\n==== Unités à moins de ", UNIT_RADIUS, " u  (état de jeu : ", fullName(gs), ")\n")
        local total, failed = 0, 0
        local okArr, errArr = pcall(function()
            gs.m_unitsPrivate:ForEach(function(_, elem)
                total = total + 1
                local okU = pcall(function()
                    local u = elem:get()
                    local tr = u.m_transform.Translation
                    local d = math.sqrt((tr.X - pl.X) ^ 2 + (tr.Y - pl.Y) ^ 2 + (tr.Z - pl.Z) ^ 2)
                    if d <= UNIT_RADIUS then
                        f:write(string.format(
                            "  id=%s type=%s cat=%s clan=%s state=%s dist=%.0f detection=%s fight=%s chasedGeneral=%s\n",
                            tostring(u.m_id), tostring(u.m_type), tostring(u.m_category), tostring(u.m_clan),
                            tostring(u.m_behaviourState), d, tostring(u.m_detectionRange), tostring(u.m_fightRadius),
                            tostring(u.m_chasedGeneral)))
                    end
                end)
                if not okU then failed = failed + 1 end
            end)
        end)
        f:write(string.format("  total unités=%d  lectures échouées=%d  tableau=%s %s\n",
            total, failed, tostring(okArr), tostring(errArr or "")))
    end
    f:close()
    print("[CockroachProbe] perception -> " .. name .. "\n")
end

local function guarded(label, fn)
    return function()
        ExecuteInGameThread(function()
            local s, e = pcall(fn)
            if not s then print("[CockroachProbe] " .. label .. " erreur: " .. tostring(e) .. "\n") end
        end)
    end
end

RegisterKeyBind(Key.F6, function()
    if recording then
        stopRecording()
    else
        ExecuteInGameThread(function() pcall(startRecording) end)
    end
end)

RegisterKeyBind(Key.F7, guarded("snapshot", snapshot))
RegisterKeyBind(Key.F9, guarded("inspect", inspect))
RegisterKeyBind(Key.F10, guarded("perception", perception))

RegisterKeyBind(Key.F8, function()
    marker = marker + 1
    print("[CockroachProbe] marker " .. marker .. "\n")
end)

print("[CockroachProbe] chargé. F6=REC  F7=snapshot  F8=marker  F9=inspect  F10=perception  out=" .. OUT_DIR .. "\n")
