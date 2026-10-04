-- CockroachProbe — UE4SS mod d'instrumentation runtime pour "Les Fourmis" (Empire of the Ants).
-- Objectif : mesurer caméra + mouvement multi-surfaces (Bible §4, phases 2-4).
-- Ne lit que des valeurs en mémoire pendant le jeu ; n'extrait aucun asset ni code.
--
-- Touches :
--   F6  démarrer / arrêter l'enregistrement CSV (frames)
--   F7  snapshot des paramètres (spring arm, caméra, movement component) -> params_*.txt
--   F8  marqueur d'événement dans le CSV (ex : "début montée mur") — incrémente le compteur
--
-- Sorties : dossier Mods/CockroachProbe/out/

local OUT_DIR = "Mods/CockroachProbe/out/"
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
    "t", "marker",
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

local function sample()
    local pc = getPC()
    if pc == nil then return end
    local pawn = getPawn(pc)
    if pawn == nil then return end
    local cm = try(function() return pc.PlayerCameraManager end)
    local arm = findComponent("SpringArmComponent", pawn)
    local move = try(function() return pawn.CharacterMovement end)

    local line = table.concat({
        string.format("%.4f", os.clock() - t0),
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

print("[CockroachProbe] chargé. F6=REC  F7=snapshot  F8=marker\n")
