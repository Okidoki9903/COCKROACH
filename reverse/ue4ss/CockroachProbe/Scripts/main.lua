-- CockroachProbe — UE4SS mod d'instrumentation runtime pour "Les Fourmis" (Empire of the Ants).
-- Objectif : mesurer caméra + mouvement multi-surfaces (Bible §4, phases 2-4).
-- Ne lit que des valeurs en mémoire pendant le jeu ; n'extrait aucun asset ni code.
--
-- Touches :
--   F6  démarrer / arrêter l'enregistrement CSV (frames)
--   F7  snapshot des paramètres (spring arm, caméra, movement component) -> params_*.txt
--   F8  marqueur d'événement dans le CSV (ex : "début montée mur") — incrémente le compteur
--   F9  inspection : classes + propriétés du pawn, de ses composants, du controller -> inspect_*.txt
--
-- Sorties : dossier <Win64>/ue4ss/Mods/CockroachProbe/out/ (à créer à l'installation)

-- Le dossier de travail du jeu est Binaries/Win64, pas le dossier du mod : on déduit
-- le chemin absolu de out/ depuis l'emplacement de ce script (…/CockroachProbe/Scripts/main.lua).
local function modDir()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("\\", "/")
    local dir = src:match("^(.*)/Scripts/[^/]+$")
    return dir or "ue4ss/Mods/CockroachProbe"
end
local OUT_DIR = modDir() .. "/out/"
local SAMPLE_MS = 16 -- ~60 Hz

local recording = false
local csv = nil
local marker = 0
local t0 = os.clock()

local function ok(o) return o ~= nil and o:IsValid() end

local function try(fn, default)
    local s, v = pcall(fn)
    if s then return v end
    return default
end

local function vec(v)
    if v == nil then return "nan,nan,nan" end
    return string.format("%.4f,%.4f,%.4f", v.X, v.Y, v.Z)
end

local function rot(r)
    if r == nil then return "nan,nan,nan" end
    return string.format("%.4f,%.4f,%.4f", r.Pitch, r.Yaw, r.Roll)
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

-- Composants trouvés par type ; on prend le premier attaché au pawn joueur si possible.
local function findComponent(className, pawn)
    local all = FindAllOf(className)
    if all == nil then return nil end
    for _, c in ipairs(all) do
        if ok(c) then
            local owner = try(function() return c:GetOwner() end)
            if pawn ~= nil and ok(owner) and owner:GetFullName() == pawn:GetFullName() then
                return c
            end
        end
    end
    for _, c in ipairs(all) do
        if ok(c) then return c end
    end
    return nil
end

local HEADER = table.concat({
    "t", "game_t", "marker",
    "pawn_x,pawn_y,pawn_z",
    "pawn_pitch,pawn_yaw,pawn_roll",
    "pawn_fwd_x,pawn_fwd_y,pawn_fwd_z",
    "pawn_right_x,pawn_right_y,pawn_right_z",
    "pawn_up_x,pawn_up_y,pawn_up_z",
    "vel_x,vel_y,vel_z",
    "cam_x,cam_y,cam_z",
    "cam_pitch,cam_yaw,cam_roll",
    "fov",
    "ctrl_pitch,ctrl_yaw,ctrl_roll",
    "arm_len",
    "grav_x,grav_y,grav_z",
    "move_mode",
}, ",")

-- Cache : FindAllOf à 60 Hz coûte cher ; on ne recherche que si le pawn change.
local cache = { pawnName = nil }

local function refreshCache(pc, pawn)
    local n = pawn:GetFullName()
    if cache.pawnName == n and ok(cache.cm) then return end
    cache.pawnName = n
    cache.cm = try(function() return pc.PlayerCameraManager end)
    cache.arm = findComponent("SpringArmComponent", pawn)
    cache.move = try(function() return pawn.CharacterMovement end)
    cache.world = try(function() return pawn:GetWorld() end)
    cache.gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
end

local function gameTime()
    if not ok(cache.gs) or not ok(cache.world) then return -1 end
    return try(function() return cache.gs:GetTimeSeconds(cache.world) end, -1)
end

local function sample()
    local pc = getPC()
    if pc == nil then return end
    local pawn = getPawn(pc)
    if pawn == nil then return end
    refreshCache(pc, pawn)
    local cm, arm, move = cache.cm, cache.arm, cache.move

    local line = table.concat({
        string.format("%.4f", os.clock() - t0),
        string.format("%.4f", gameTime()),
        tostring(marker),
        vec(try(function() return pawn:K2_GetActorLocation() end)),
        rot(try(function() return pawn:K2_GetActorRotation() end)),
        vec(try(function() return pawn:GetActorForwardVector() end)),
        vec(try(function() return pawn:GetActorRightVector() end)),
        vec(try(function() return pawn:GetActorUpVector() end)),
        vec(try(function() return pawn:GetVelocity() end)),
        vec(ok(cm) and try(function() return cm:GetCameraLocation() end) or nil),
        rot(ok(cm) and try(function() return cm:GetCameraRotation() end) or nil),
        string.format("%.3f", ok(cm) and try(function() return cm:GetFOVAngle() end, -1) or -1),
        rot(try(function() return pc:GetControlRotation() end)),
        string.format("%.3f", ok(arm) and try(function() return arm.TargetArmLength end, -1) or -1),
        -- UE 5.4+ : gravité arbitraire par CharacterMovement ; absent sinon -> nan
        vec(ok(move) and try(function() return move:GetGravityDirection() end) or nil),
        tostring(ok(move) and try(function() return move.MovementMode end, -1) or -1),
    }, ",")
    csv:write(line, "\n")
end

local function startRecording()
    local name = OUT_DIR .. "frames_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    csv = io.open(name, "w")
    if csv == nil then
        print("[CockroachProbe] impossible d'ouvrir " .. name .. " (créer le dossier out/)\n")
        return
    end
    csv:write(HEADER, "\n")
    t0 = os.clock()
    marker = 0
    recording = true
    print("[CockroachProbe] REC -> " .. name .. "\n")
    LoopAsync(SAMPLE_MS, function()
        if not recording then return true end -- true = arrêter la boucle
        ExecuteInGameThread(function()
            if recording and csv ~= nil then pcall(sample) end
        end)
        return false
    end)
end

local function stopRecording()
    recording = false
    if csv ~= nil then csv:close() csv = nil end
    print("[CockroachProbe] STOP\n")
end

-- Snapshot de propriétés connues d'UE. Les classes custom du jeu sont à explorer
-- via la Live View d'UE4SS, puis à ajouter ici.
local SNAPSHOT = {
    SpringArmComponent = {
        "TargetArmLength", "SocketOffset", "TargetOffset", "ProbeSize",
        "bDoCollisionTest", "bUsePawnControlRotation", "bInheritPitch", "bInheritYaw", "bInheritRoll",
        "bEnableCameraLag", "bEnableCameraRotationLag", "CameraLagSpeed",
        "CameraRotationLagSpeed", "CameraLagMaxDistance", "bUseCameraLagSubstepping",
    },
    CameraComponent = {
        "FieldOfView", "AspectRatio", "bConstrainAspectRatio", "PostProcessBlendWeight",
    },
    CharacterMovementComponent = {
        "MaxWalkSpeed", "MaxAcceleration", "BrakingDecelerationWalking", "GroundFriction",
        "RotationRate", "bOrientRotationToMovement", "bUseControllerDesiredRotation",
        "MaxStepHeight", "WalkableFloorAngle", "WalkableFloorZ", "GravityScale",
        "JumpZVelocity", "AirControl", "MaxCustomMovementSpeed", "CustomMovementMode",
    },
    CapsuleComponent = { "CapsuleRadius", "CapsuleHalfHeight" },
    PlayerCameraManager = { "DefaultFOV", "ViewPitchMin", "ViewPitchMax", "ViewYawMin", "ViewYawMax", "ViewRollMin", "ViewRollMax" },
}

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

local function snapshot()
    local pc = getPC()
    local pawn = pc and getPawn(pc) or nil
    local name = OUT_DIR .. "params_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(name, "w")
    if f == nil then return end
    if pawn ~= nil then
        f:write("# Pawn: ", pawn:GetFullName(), "\n")
        f:write("# Pawn class: ", try(function() return pawn:GetClass():GetFullName() end, "?"), "\n\n")
    end
    for cls, props in pairs(SNAPSHOT) do
        local obj
        if cls == "PlayerCameraManager" then
            obj = pc and try(function() return pc.PlayerCameraManager end) or nil
        else
            obj = findComponent(cls, pawn)
        end
        f:write("[", cls, "] ", ok(obj) and obj:GetFullName() or "(introuvable)", "\n")
        if ok(obj) then
            for _, p in ipairs(props) do
                f:write("  ", p, " = ", fmt(try(function() return obj[p] end)), "\n")
            end
        end
        f:write("\n")
    end
    f:close()
    print("[CockroachProbe] snapshot -> " .. name .. "\n")
end

-- F9 : inspection par réflexion. Pour le pawn, ses composants, le controller et le camera
-- manager : chaîne de classes + toutes les propriétés (nom, type, valeur). Sert à trouver
-- les classes custom (mouvement mural, caméra) et le nom de leurs vrais paramètres.
local function className(o)
    return try(function() return o:GetClass():GetFName():ToString() end, "?")
end

local function classChain(o)
    local names = {}
    local c = try(function() return o:GetClass() end)
    while c ~= nil and try(function() return c:IsValid() end, false) do
        names[#names + 1] = try(function() return c:GetFullName() end, "?")
        c = try(function() return c:GetSuperStruct() end)
    end
    return table.concat(names, "\n#   <- ")
end

local function dumpProps(f, o)
    local c = try(function() return o:GetClass() end)
    while c ~= nil and try(function() return c:IsValid() end, false) do
        local cname = try(function() return c:GetFName():ToString() end, "?")
        try(function()
            c:ForEachProperty(function(prop)
                local pname = prop:GetFName():ToString()
                local ptype = try(function() return prop:GetClass():GetFName():ToString() end, "?")
                local val = ""
                if ptype:match("Float") or ptype:match("Double") or ptype:match("Int") or ptype:match("Bool")
                    or ptype:match("Byte") or ptype:match("Enum") or ptype:match("Struct") or ptype:match("Name") then
                    val = fmt(try(function() return o[pname] end))
                elseif ptype:match("Object") then
                    local v = try(function() return o[pname] end)
                    val = (v ~= nil and try(function() return v:IsValid() end, false)) and v:GetFullName() or "None"
                end
                f:write(string.format("  %-22s %-40s %-26s = %s\n", cname, pname, ptype, val))
            end)
        end)
        c = try(function() return c:GetSuperStruct() end)
        -- On s'arrête aux classes de base sans intérêt.
        local n = c and try(function() return c:GetFName():ToString() end, "") or ""
        if n == "Object" or n == "Actor" or n == "ActorComponent" then break end
    end
end

local function inspectObj(f, label, o)
    f:write("\n==== ", label, " : ", ok(o) and o:GetFullName() or "(introuvable)", "\n")
    if not ok(o) then return end
    f:write("# ", classChain(o), "\n")
    dumpProps(f, o)
end

local function inspect()
    local pc = getPC()
    local pawn = pc and getPawn(pc) or nil
    local name = OUT_DIR .. "inspect_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(name, "w")
    if f == nil then
        print("[CockroachProbe] impossible d'ouvrir " .. name .. "\n")
        return
    end
    inspectObj(f, "PlayerController", pc)
    inspectObj(f, "PlayerCameraManager", pc and try(function() return pc.PlayerCameraManager end) or nil)
    inspectObj(f, "Pawn", pawn)
    if pawn ~= nil then
        local acClass = StaticFindObject("/Script/Engine.ActorComponent")
        local comps = try(function() return pawn:K2_GetComponentsByClass(acClass) end)
        if comps ~= nil then
            local list = {}
            try(function() comps:ForEach(function(_, e) list[#list + 1] = e:get() end) end)
            if #list == 0 then
                try(function() for _, e in ipairs(comps) do list[#list + 1] = e end end)
            end
            f:write("\n# Composants du pawn : ", #list, "\n")
            for _, comp in ipairs(list) do
                f:write("#   ", className(comp), "  ", ok(comp) and comp:GetFullName() or "?", "\n")
            end
            for _, comp in ipairs(list) do
                inspectObj(f, "Component " .. className(comp), comp)
            end
        end
    end
    f:close()
    print("[CockroachProbe] inspect -> " .. name .. "\n")
end

RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        local s, e = pcall(inspect)
        if not s then print("[CockroachProbe] inspect erreur: " .. tostring(e) .. "\n") end
    end)
end)

RegisterKeyBind(Key.F6, function()
    if recording then stopRecording() else startRecording() end
end)

RegisterKeyBind(Key.F7, function()
    ExecuteInGameThread(function() pcall(snapshot) end)
end)

RegisterKeyBind(Key.F8, function()
    marker = marker + 1
    print("[CockroachProbe] marker " .. marker .. "\n")
end)

print("[CockroachProbe] chargé. F6=REC  F7=snapshot  F8=marker  F9=inspect  out=" .. OUT_DIR .. "\n")
