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
    }, ",")
    csv:write(line, "\n")
end

local loopHandle = nil
local recGen = 0 -- numéro d'enregistrement : une vieille boucle survivante ne doit rien faire

local function closeCsv()
    local wasOpen = csv ~= nil
    if csv ~= nil then csv:close() csv = nil end
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

RegisterKeyBind(Key.F8, function()
    marker = marker + 1
    print("[CockroachProbe] marker " .. marker .. "\n")
end)

print("[CockroachProbe] chargé. F6=REC  F7=snapshot  F8=marker  F9=inspect  out=" .. OUT_DIR .. "\n")
