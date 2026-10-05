//! COCKROACH — prototype jouable.
//!
//! Scène « cuisine » à l'échelle d'un cafard (1 u = 1 cm, rayon du corps 1 cm) ; caméra et marche
//! multi-surfaces d'après docs/specs/. Commandes identiques à Les Fourmis.
//!
//! Manette : stick G = marcher (vitesse ∝ inclinaison), stick D = caméra, B = courir (maintenir),
//!           Y = saut (maintenir puis relâcher ; appui bref sur mur/plafond = lâcher prise),
//!           clic stick G = distance caméra.
//! Clavier/souris : ZQSD/WASD, souris (clic pour capturer, Échap pour libérer), Maj = courir,
//!           Espace = saut, Tab ou M = distance caméra. F1 = debug sondes, R = replacer le cafard.

use avian3d::prelude::*;
use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::light::CascadeShadowConfigBuilder;
use bevy::prelude::*;
use bevy::window::{CursorGrabMode, CursorOptions, PrimaryWindow};

mod game_loop;
mod human;

use cockroach_proto::camera_rig::CameraRig;
use cockroach_proto::perception::Awareness;
use cockroach_proto::query::{Hit, SurfaceQuery};
use cockroach_proto::tuning::Tuning;
use cockroach_proto::walker::{Mode, MoveInput, Walker};

/// Rayon du corps du cafard (cm).
const ROACH_RADIUS: f32 = 1.0;
/// Point de départ : dans le refuge, sous le meuble bas.
const SPAWN: Vec3 = Vec3::new(-120.0, ROACH_RADIUS, -125.0);
/// Position du soleil (lumière directionnelle) : sert aussi au test d'ombre de la perception.
const SUN_POSITION: Vec3 = Vec3::new(150.0, 200.0, 120.0);
const MOUSE_SENSITIVITY: f32 = 0.0025; // rad / pixel
const LOOK_DEADZONE: f32 = 0.15;

fn main() {
    App::new()
        .add_plugins((
            DefaultPlugins.set(WindowPlugin {
                primary_window: Some(Window { title: "COCKROACH — prototype".into(), ..default() }),
                ..default()
            }),
            PhysicsPlugins::default(),
            human::HumanPlugin,
            game_loop::GameLoopPlugin,
        ))
        .insert_resource(ClearColor(Color::srgb(0.05, 0.05, 0.06)))
        .insert_resource(GlobalAmbientLight { brightness: 250.0, ..default() })
        .insert_resource(Settings { tuning: Tuning::scaled(ROACH_RADIUS), debug: false })
        .init_resource::<PlayerInput>()
        .add_systems(Startup, (spawn_scene, spawn_player, spawn_hud))
        .add_systems(
            Update,
            (read_input, step_player, human::update_human, game_loop::update_game, game_loop::update_colony_visuals, update_camera, update_roach_visual, update_hud, draw_debug)
                .chain(),
        )
        .run();
}

// ------------------------------------------------------------------ ressources & composants

#[derive(Resource)]
struct Settings {
    tuning: Tuning,
    debug: bool,
}

#[derive(Resource, Default)]
struct PlayerInput {
    stick: Vec2,
    look: Vec2,
    mouse: Vec2,
    run: bool,
    jump: bool,
    cycle_arm: bool,
    reset: bool,
}

#[derive(Resource)]
struct Player {
    walker: Walker,
    rig: CameraRig,
    frames: u32,
}

#[derive(Component)]
struct Roach;

#[derive(Component)]
struct MainCamera;

#[derive(Component)]
struct Hud;

/// Adaptateur Avian → trait de requêtes de la logique.
struct AvianQuery<'a, 'w, 's> {
    spatial: &'a SpatialQuery<'w, 's>,
    filter: SpatialQueryFilter,
}

impl SurfaceQuery for AvianQuery<'_, '_, '_> {
    fn ray(&self, origin: Vec3, dir: Vec3, max_distance: f32) -> Option<Hit> {
        let dir = Dir3::new(dir).ok()?;
        self.spatial
            .cast_ray(origin, dir, max_distance, false, &self.filter)
            .map(|h| Hit { distance: h.distance, normal: h.normal })
    }

    fn sphere(&self, origin: Vec3, dir: Vec3, radius: f32, max_distance: f32) -> Option<Hit> {
        let dir = Dir3::new(dir).ok()?;
        self.spatial
            .cast_shape(
                &Collider::sphere(radius),
                origin,
                Quat::IDENTITY,
                dir,
                &ShapeCastConfig::from_max_distance(max_distance),
                &self.filter,
            )
            .map(|h| Hit { distance: h.distance, normal: h.normal2 })
    }
}

// ------------------------------------------------------------------ scène

fn spawn_scene(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let mut mat = |r: f32, g: f32, b: f32, rough: f32| {
        materials.add(StandardMaterial { base_color: Color::srgb(r, g, b), perceptual_roughness: rough, ..default() })
    };
    let tile = mat(0.75, 0.72, 0.66, 0.6);
    let wall = mat(0.82, 0.80, 0.74, 0.9);
    let wood = mat(0.45, 0.30, 0.18, 0.7);
    let cabinet = mat(0.30, 0.38, 0.33, 0.6);
    let fridge = mat(0.90, 0.90, 0.92, 0.3);
    let board = mat(0.70, 0.55, 0.35, 0.8);
    let metal = mat(0.60, 0.62, 0.65, 0.25);
    let book = mat(0.55, 0.15, 0.12, 0.8);

    let mut cuboid = |commands: &mut Commands, center: Vec3, size: Vec3, rot: Quat, material: Handle<StandardMaterial>| {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
            MeshMaterial3d(material),
            Transform::from_translation(center).with_rotation(rot),
            RigidBody::Static,
            Collider::cuboid(size.x, size.y, size.z),
        ));
    };
    let q0 = Quat::IDENTITY;
    // Pièce 400 × 250 × 300 cm (sol à y = 0).
    cuboid(&mut commands, Vec3::new(0.0, -5.0, 0.0), Vec3::new(420.0, 10.0, 320.0), q0, tile);
    cuboid(&mut commands, Vec3::new(0.0, 255.0, 0.0), Vec3::new(420.0, 10.0, 320.0), q0, wall.clone());
    cuboid(&mut commands, Vec3::new(0.0, 125.0, -155.0), Vec3::new(420.0, 250.0, 10.0), q0, wall.clone());
    cuboid(&mut commands, Vec3::new(0.0, 125.0, 155.0), Vec3::new(420.0, 250.0, 10.0), q0, wall.clone());
    cuboid(&mut commands, Vec3::new(-205.0, 125.0, 0.0), Vec3::new(10.0, 250.0, 300.0), q0, wall.clone());
    cuboid(&mut commands, Vec3::new(205.0, 125.0, 0.0), Vec3::new(10.0, 250.0, 300.0), q0, wall);
    // Table : plateau (dessous praticable) + 4 pieds.
    cuboid(&mut commands, Vec3::new(0.0, 75.0, -40.0), Vec3::new(120.0, 4.0, 80.0), q0, wood.clone());
    for (x, z) in [(-55.0, -75.0), (55.0, -75.0), (-55.0, -5.0), (55.0, -5.0)] {
        cuboid(&mut commands, Vec3::new(x, 36.5, z), Vec3::new(5.0, 73.0, 5.0), q0, wood.clone());
    }
    // Meuble bas + plan de travail en surplomb, frigo.
    // Meuble bas surélevé de 4 cm sur pieds : le dessous est le refuge du cafard.
    cuboid(&mut commands, Vec3::new(-120.0, 45.0, -127.0), Vec3::new(150.0, 82.0, 46.0), q0, cabinet.clone());
    for (x, z) in [(-192.0, -147.0), (-48.0, -147.0), (-192.0, -107.0), (-48.0, -107.0)] {
        cuboid(&mut commands, Vec3::new(x, 2.0, z), Vec3::new(3.0, 4.0, 3.0), q0, cabinet.clone());
    }
    cuboid(&mut commands, Vec3::new(-120.0, 88.0, -122.0), Vec3::new(156.0, 4.0, 56.0), q0, wood.clone());
    cuboid(&mut commands, Vec3::new(160.0, 90.0, -115.0), Vec3::new(70.0, 180.0, 70.0), q0, fridge);
    // Planche à découper debout (paroi fine : on passe d'une face à l'autre).
    cuboid(&mut commands, Vec3::new(40.0, 15.0, 40.0), Vec3::new(30.0, 30.0, 1.5), q0, board);
    // Pile de livres (marches) et rampe inclinée.
    for (i, (h, w)) in [(4.0, 30.0), (4.0, 24.0), (4.0, 18.0)].into_iter().enumerate() {
        cuboid(&mut commands, Vec3::new(-70.0, 2.0 + 4.0 * i as f32, 70.0), Vec3::new(w, h, 22.0), q0, book.clone());
    }
    cuboid(&mut commands, Vec3::new(100.0, 6.0, 60.0), Vec3::new(40.0, 1.5, 20.0), Quat::from_rotation_z(0.35), wood);
    // Boîte de conserve (surface courbe).
    commands.spawn((
        Mesh3d(meshes.add(Cylinder::new(4.0, 12.0))),
        MeshMaterial3d(metal),
        Transform::from_xyz(-30.0, 6.0, 30.0),
        RigidBody::Static,
        Collider::cylinder(4.0, 12.0),
    ));

    // Lumière : soleil rasant par la fenêtre + ambiance faible.
    commands.spawn((
        DirectionalLight { illuminance: 6000.0, shadow_maps_enabled: true, ..default() },
        Transform::from_translation(SUN_POSITION).looking_at(Vec3::ZERO, Vec3::Y),
        CascadeShadowConfigBuilder { maximum_distance: 600.0, first_cascade_far_bound: 40.0, ..default() }.build(),
    ));
}

fn spawn_player(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    settings: Res<Settings>,
) {
    let t = &settings.tuning;
    let walker = Walker::new(SPAWN, Vec3::Z);
    // caméra tournée vers la sortie du refuge (+Z)
    let rig = CameraRig::new(std::f32::consts::PI, (-8f32).to_radians());
    commands.insert_resource(Player { walker, rig, frames: 0 });

    let chitin = materials.add(StandardMaterial {
        base_color: Color::srgb(0.28, 0.14, 0.06),
        perceptual_roughness: 0.3,
        reflectance: 0.6,
        ..default()
    });
    let dark = materials.add(StandardMaterial { base_color: Color::srgb(0.12, 0.06, 0.03), ..default() });
    let r = ROACH_RADIUS;
    let sphere = meshes.add(Sphere::new(1.0));
    let stick = meshes.add(Cuboid::new(1.0, 1.0, 1.0));
    // Repère local du cafard : +Y = up, -Z = avant. Le corps touche la surface (centre à R au-dessus).
    commands
        .spawn((Roach, Transform::from_translation(SPAWN), Visibility::default()))
        .with_children(|p| {
            p.spawn((
                Mesh3d(sphere.clone()),
                MeshMaterial3d(chitin.clone()),
                Transform::from_xyz(0.0, -0.55 * r, 0.1 * r).with_scale(Vec3::new(0.75, 0.38, 1.45) * r),
            ));
            p.spawn((
                Mesh3d(sphere.clone()),
                MeshMaterial3d(dark.clone()),
                Transform::from_xyz(0.0, -0.6 * r, -1.45 * r).with_scale(Vec3::new(0.4, 0.28, 0.35) * r),
            ));
            for side in [-1.0f32, 1.0] {
                // antennes
                p.spawn((
                    Mesh3d(stick.clone()),
                    MeshMaterial3d(dark.clone()),
                    Transform::from_xyz(side * 0.35 * r, -0.45 * r, -2.6 * r)
                        .with_rotation(Quat::from_rotation_y(side * 0.35) * Quat::from_rotation_x(0.12))
                        .with_scale(Vec3::new(0.04, 0.04, 2.4) * r),
                ));
                // pattes
                for (i, z) in [-0.7f32, 0.1, 0.9].into_iter().enumerate() {
                    let splay = (i as f32 - 1.0) * 0.5;
                    p.spawn((
                        Mesh3d(stick.clone()),
                        MeshMaterial3d(dark.clone()),
                        Transform::from_xyz(side * 0.9 * r, -0.8 * r, z * r)
                            .with_rotation(Quat::from_rotation_y(side * splay) * Quat::from_rotation_z(side * 0.5))
                            .with_scale(Vec3::new(1.1, 0.06, 0.06) * r),
                    ));
                }
            }
        });

    commands.spawn((
        MainCamera,
        Camera3d::default(),
        Projection::Perspective(PerspectiveProjection { near: t.cam_near, ..default() }),
        Transform::from_translation(SPAWN + Vec3::new(0.0, 5.0, 20.0)).looking_at(SPAWN, Vec3::Y),
    ));
}

fn spawn_hud(mut commands: Commands) {
    commands.spawn((
        Hud,
        Text::new(""),
        TextFont::from_font_size(FontSize::Px(15.0)),
        TextColor(Color::srgb(0.95, 0.92, 0.85)),
        Node { position_type: PositionType::Absolute, top: Val::Px(10.0), left: Val::Px(12.0), ..default() },
    ));
}

// ------------------------------------------------------------------ systèmes

fn read_input(
    keys: Res<ButtonInput<KeyCode>>,
    mouse_buttons: Res<ButtonInput<MouseButton>>,
    mouse_motion: Res<AccumulatedMouseMotion>,
    gamepads: Query<&Gamepad>,
    mut cursor: Single<&mut CursorOptions, With<PrimaryWindow>>,
    mut input: ResMut<PlayerInput>,
    mut settings: ResMut<Settings>,
) {
    let mut stick = Vec2::ZERO;
    let mut look = Vec2::ZERO;
    let mut run = false;
    let mut jump = false;
    let mut cycle_arm = false;
    let mut restart = false;

    if let Some(pad) = gamepads.iter().next() {
        stick = pad.left_stick();
        look = pad.right_stick();
        run = pad.pressed(GamepadButton::East);
        jump = pad.pressed(GamepadButton::North);
        cycle_arm = pad.just_pressed(GamepadButton::LeftThumb);
        restart = pad.just_pressed(GamepadButton::Start);
    }
    // KeyCode = position physique : W/A/S/D = Z/Q/S/D sur AZERTY.
    let axis = |neg: KeyCode, pos: KeyCode| (keys.pressed(pos) as i32 - keys.pressed(neg) as i32) as f32;
    let kb = Vec2::new(axis(KeyCode::KeyA, KeyCode::KeyD), axis(KeyCode::KeyS, KeyCode::KeyW));
    if kb != Vec2::ZERO {
        stick = kb.normalize();
    }
    run |= keys.pressed(KeyCode::ShiftLeft);
    jump |= keys.pressed(KeyCode::Space);
    cycle_arm |= keys.just_pressed(KeyCode::Tab) || keys.just_pressed(KeyCode::KeyM);

    // Souris : clic = capturer, Échap = libérer.
    if mouse_buttons.just_pressed(MouseButton::Left) {
        cursor.grab_mode = CursorGrabMode::Locked;
        cursor.visible = false;
    }
    if keys.just_pressed(KeyCode::Escape) {
        cursor.grab_mode = CursorGrabMode::None;
        cursor.visible = true;
    }
    let captured = cursor.grab_mode != CursorGrabMode::None;
    let d = mouse_motion.delta;
    input.mouse = if captured { Vec2::new(d.x, -d.y) * MOUSE_SENSITIVITY } else { Vec2::ZERO };

    input.stick = stick.clamp_length_max(1.0);
    // zone morte du stick caméra (dérive), avec remise à l'échelle
    let l = look.length().min(1.0);
    input.look = if l < LOOK_DEADZONE { Vec2::ZERO } else { look / look.length() * (l - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE) };
    input.run = run;
    input.jump = jump;
    input.cycle_arm = cycle_arm;
    input.reset = keys.just_pressed(KeyCode::KeyR) || restart;
    if keys.just_pressed(KeyCode::F1) {
        settings.debug = !settings.debug;
    }
}

fn step_player(
    time: Res<Time>,
    input: Res<PlayerInput>,
    settings: Res<Settings>,
    spatial: SpatialQuery,
    mut game: ResMut<game_loop::GameLoop>,
    mut player: ResMut<Player>,
) {
    // Porter une miette ralentit ; piège collant ou fin de partie = immobile.
    let mut tuning = settings.tuning.clone();
    tuning.walk_speed *= game.speed_factor;
    tuning.run_speed *= game.speed_factor;
    let t = &tuning;
    let dt = time.delta_secs();
    let player = &mut *player;
    player.frames += 1;
    if input.reset && game.phase == game_loop::Phase::Playing {
        // « replacer » : retour au refuge, mais on lâche la miette (pas de raccourci)
        player.walker = Walker::new(SPAWN, Vec3::Z);
        game.carrying = false;
    }
    if input.cycle_arm {
        player.rig.cycle_arm();
    }
    player.rig.rotate(input.look, input.mouse, t, dt);
    // Les colliders statiques ne sont indexés qu'après la première étape physique.
    if player.frames < 3 {
        return;
    }
    let q = AvianQuery { spatial: &spatial, filter: SpatialQueryFilter::default() };
    let move_input = MoveInput {
        stick: input.stick,
        run: input.run,
        jump: input.jump,
        cam_forward: player.rig.forward(),
        cam_up: player.rig.up(),
    };
    player.walker.step(&move_input, &q, t, dt);
}

fn update_camera(
    time: Res<Time>,
    settings: Res<Settings>,
    spatial: SpatialQuery,
    window: Single<&Window, With<PrimaryWindow>>,
    mut player: ResMut<Player>,
    mut camera: Single<(&mut Transform, &mut Projection), With<MainCamera>>,
    mut roach_vis: Single<&mut Visibility, With<Roach>>,
) {
    let t = &settings.tuning;
    let q = AvianQuery { spatial: &spatial, filter: SpatialQueryFilter::default() };
    let player = &mut *player;
    let running = player.walker.mode == Mode::Run;
    let out = player.rig.update(player.walker.position, player.walker.up, running, &q, t, time.delta_secs());
    let (transform, projection) = &mut *camera;
    transform.translation = out.position;
    transform.rotation = out.rotation;
    // FOV horizontal fixe (90°) → FOV vertical selon le ratio de la fenêtre.
    if let Projection::Perspective(p) = projection.as_mut() {
        let aspect = window.width() / window.height().max(1.0);
        p.fov = 2.0 * ((t.cam_fov_horizontal * 0.5).tan() / aspect).atan();
        p.near = t.cam_near;
    }
    **roach_vis = if out.hide_pawn { Visibility::Hidden } else { Visibility::Inherited };
}

fn update_roach_visual(player: Res<Player>, mut roach: Single<&mut Transform, With<Roach>>) {
    let w = &player.walker;
    roach.translation = w.position;
    // Repère : x = droite, y = up, z = -avant.
    roach.rotation = Quat::from_mat3(&Mat3::from_cols(w.right(), w.up, -w.forward));
}

fn update_hud(
    time: Res<Time>,
    settings: Res<Settings>,
    player: Res<Player>,
    humans: Query<&human::Human>,
    tuning: Res<human::HumanTuning>,
    game: Res<game_loop::GameLoop>,
    mut hud: Single<&mut Text, With<Hud>>,
) {
    let t = &settings.tuning;
    let w = &player.walker;
    let speed = w.velocity.length();
    let surface = w.up.angle_between(Vec3::Y).to_degrees();
    let surface_name = match surface {
        a if a < 30.0 => "sol",
        a if a < 150.0 => "mur",
        _ => "plafond",
    };
    let arm = t.arm_lengths[player.rig.arm_index];
    let fps = if time.delta_secs() > 0.0 { 1.0 / time.delta_secs() } else { 0.0 };
    let human = humans.iter().next();
    let mut human_line = game_loop::hud_lines(&game, human, w.position);
    if let Some(h) = human.filter(|h| h.present) {
        let s = h.suspicion.value;
        let filled = (s / 5.0).round() as usize;
        let state = match h.suspicion.awareness(&tuning.0) {
            Awareness::Calm => "calme",
            Awareness::Notice => "REMARQUE",
            Awareness::Search => "CHERCHE",
            Awareness::Detected => "DETECTE !",
        };
        let v = h.last_visibility;
        human_line += &format!(
            "Humain : [{}{}] {s:.0}/100 {state}   vu : {:.2} (dist {:.0} cm{}{})\n",
            "#".repeat(filled.min(20)),
            "-".repeat(20 - filled.min(20)),
            v.value,
            v.distance,
            if v.line_of_sight { "" } else { ", cache" },
            if h.in_shadow { ", ombre" } else { "" },
        );
    }
    hud.0 = human_line + &format!(
        "COCKROACH - prototype   ({fps:.0} i/s)\n\
         Etat : {:?}   vitesse : {speed:.1} cm/s ({:.1} corps/s)\n\
         Surface : {surface_name} ({surface:.0} deg)   endurance : {:.0} %\n\
         Camera : bras {arm:.1} cm   pitch {:.0} deg\n\
         \n\
         Manette : stick G marcher | stick D camera | B courir | Y sauter | clic stick G distance\n\
         Clavier : ZQSD/WASD | souris (clic) | Maj courir | Espace sauter | Tab distance\n\
         F1 debug sondes | R replacer (lache la miette) | R/Start rejouer apres la fin",
        w.mode,
        speed / t.body_radius,
        w.stamina * 100.0,
        player.rig.pitch.to_degrees(),
    );
}

fn draw_debug(settings: Res<Settings>, player: Res<Player>, mut gizmos: Gizmos) {
    if !settings.debug {
        return;
    }
    let w = &player.walker;
    let r = settings.tuning.body_radius;
    gizmos.arrow(w.position, w.position + w.up * 3.0 * r, Color::srgb(0.2, 1.0, 0.3));
    gizmos.arrow(w.position, w.position + w.target_up * 3.0 * r, Color::srgb(1.0, 0.9, 0.2));
    gizmos.arrow(w.position, w.position + w.forward * 3.0 * r, Color::srgb(0.3, 0.6, 1.0));
    for c in &w.contacts {
        let col = Color::srgb(1.0, 1.0 - c.weight, 1.0 - c.weight);
        gizmos.line(w.position, c.point, col.with_alpha(0.25 + 0.75 * c.weight));
    }
}
