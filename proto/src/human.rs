//! Humain : rythme de présence, patrouille, regard, perception et suspicion (docs/specs/perception.md §B).
//!
//! Il entre dans la cuisine, patrouille ~45 s puis sort ~25 s (fenêtre pour sortir du refuge).
//! Calme → patrouille en balayant du regard ; Remarque (≥ 30) → s'arrête et regarde la dernière position vue ;
//! Cherche (≥ 60) → marche vers elle ; Détecté (100) → vient écraser le cafard s'il est au sol (zone rouge).
//! Les détections et écrasements sont envoyés à la boucle de jeu (`GameEvents`).
//! L'humain n'a pas de collider : le cafard ne peut pas (encore) lui grimper dessus.

use std::f32::consts::TAU;

use avian3d::prelude::*;
use bevy::prelude::*;

use cockroach_proto::perception::{Awareness, Observer, PerceptionTuning, Suspicion, Target, Visibility as Sight, visibility};
use cockroach_proto::query::SurfaceQuery;
use cockroach_proto::walker::Walker;

use crate::game_loop::{GameEvents, GameLoop, Phase};
use crate::{AvianQuery, Player, ROACH_RADIUS, SUN_POSITION, Settings};

const EYE_HEIGHT: f32 = 160.0;
const BODY_RADIUS: f32 = 18.0;
const WALK_SPEED: f32 = 110.0;
const SEARCH_SPEED: f32 = 80.0;
const CHASE_SPEED: f32 = 150.0;
const TURN_SPEED: f32 = 3.0; // rad/s, pour le corps et le regard
const SWEEP_ANGLE: f32 = 0.6; // ±35° de balayage du regard en patrouille
const SWEEP_PERIOD: f32 = 5.0;
/// Rayon horizontal d'un pied (zone d'écrasement effective = pied + zone rouge).
const FOOT_RADIUS: f32 = 14.0;
const PRESENT_TIME: f32 = 45.0;
const AWAY_TIME: f32 = 25.0;
/// Porte de la cuisine (l'humain y apparaît et y disparaît).
const DOOR: Vec3 = Vec3::new(185.0, 0.0, 135.0);
const PATROL: [Vec3; 4] = [
    Vec3::new(-140.0, 0.0, 100.0),
    Vec3::new(140.0, 0.0, 100.0),
    Vec3::new(140.0, 0.0, 30.0),
    Vec3::new(-140.0, 0.0, 30.0),
];

pub struct HumanPlugin;

impl Plugin for HumanPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(HumanTuning(PerceptionTuning::human(EYE_HEIGHT, ROACH_RADIUS)))
            .add_systems(Startup, spawn_human);
    }
}

#[derive(Resource)]
pub struct HumanTuning(pub PerceptionTuning);

#[derive(Component)]
pub struct Human {
    pub position: Vec3,
    pub facing: Vec3,
    pub gaze: Vec3,
    pub waypoint: usize,
    pub suspicion: Suspicion,
    pub last_visibility: Sight,
    pub in_shadow: bool,
    /// Dans la cuisine ?
    pub present: bool,
    /// Temps restant dans la phase présente / absente (s).
    pub schedule: f32,
    leaving: bool,
    was_detected: bool,
    sweep_time: f32,
}

impl Human {
    fn new() -> Self {
        let facing = (PATROL[1] - PATROL[0]).normalize();
        Self {
            position: PATROL[0],
            facing,
            gaze: facing,
            waypoint: 1,
            suspicion: Suspicion::default(),
            last_visibility: Sight::default(),
            in_shadow: false,
            present: true,
            schedule: PRESENT_TIME,
            leaving: false,
            was_detected: false,
            sweep_time: 0.0,
        }
    }
}

pub fn reset_human(h: &mut Human) {
    *h = Human::new();
}

#[derive(Component)]
pub struct HumanHead;

#[derive(Resource)]
pub struct HeadMaterials {
    calm: Handle<StandardMaterial>,
    notice: Handle<StandardMaterial>,
    search: Handle<StandardMaterial>,
    detected: Handle<StandardMaterial>,
}

fn spawn_human(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let mat = |m: &mut Assets<StandardMaterial>, r: f32, g: f32, b: f32| {
        m.add(StandardMaterial { base_color: Color::srgb(r, g, b), perceptual_roughness: 0.8, ..default() })
    };
    let heads = HeadMaterials {
        calm: mat(&mut materials, 0.85, 0.70, 0.58),
        notice: mat(&mut materials, 0.95, 0.85, 0.20),
        search: mat(&mut materials, 0.95, 0.50, 0.10),
        detected: mat(&mut materials, 0.90, 0.10, 0.08),
    };
    let clothes = mat(&mut materials, 0.25, 0.32, 0.45);
    let shoes = mat(&mut materials, 0.10, 0.10, 0.10);
    let human = Human::new();
    let start = human.position;
    commands
        .spawn((human, Transform::from_translation(start), Visibility::default()))
        .with_children(|p| {
            // Jambes, chaussures, torse : repère local +Y haut, -Z avant.
            for x in [-9.0f32, 9.0] {
                p.spawn((
                    Mesh3d(meshes.add(Capsule3d::new(7.0, 70.0))),
                    MeshMaterial3d(clothes.clone()),
                    Transform::from_xyz(x, 45.0, 0.0),
                ));
                p.spawn((
                    Mesh3d(meshes.add(Cuboid::new(11.0, 7.0, 28.0))),
                    MeshMaterial3d(shoes.clone()),
                    Transform::from_xyz(x, 3.5, -6.0),
                ));
            }
            p.spawn((
                Mesh3d(meshes.add(Capsule3d::new(BODY_RADIUS, 50.0))),
                MeshMaterial3d(clothes.clone()),
                Transform::from_xyz(0.0, 118.0, 0.0),
            ));
        });
    // Tête séparée : elle suit le regard.
    commands.spawn((
        HumanHead,
        Mesh3d(meshes.add(Sphere::new(11.0))),
        MeshMaterial3d(heads.calm.clone()),
        Transform::from_translation(start + Vec3::Y * EYE_HEIGHT),
        Visibility::default(),
        children![(
            Mesh3d(meshes.add(Cuboid::new(3.0, 3.0, 8.0))),
            MeshMaterial3d(heads.calm.clone()),
            Transform::from_xyz(0.0, 0.0, -11.0),
        )],
    ));
    commands.insert_resource(heads);
}

fn turn_towards(current: Vec3, target: Vec3, max_angle: f32) -> Vec3 {
    let angle = current.angle_between(target);
    if angle <= max_angle || angle < 1e-4 {
        return target;
    }
    let axis = current.cross(target).try_normalize().unwrap_or(Vec3::Y);
    (Quat::from_axis_angle(axis, max_angle) * current).normalize()
}

fn flat(v: Vec3) -> Vec3 {
    Vec3::new(v.x, 0.0, v.z).normalize_or_zero()
}

fn horizontal_distance(a: Vec3, b: Vec3) -> f32 {
    Vec3::new(a.x - b.x, 0.0, a.z - b.z).length()
}

/// Le cafard est-il à l'ombre ? Rayon vers le soleil de la scène.
fn roach_in_shadow(q: &impl SurfaceQuery, w: &Walker) -> bool {
    let origin = w.position + w.up * ROACH_RADIUS * 0.6;
    let to_sun = (SUN_POSITION - origin).normalize();
    q.ray(origin, to_sun, 2000.0).is_some()
}

/// Avance vers `to` (au sol) ; retourne la distance horizontale restante.
fn walk_towards(h: &mut Human, to: Vec3, speed: f32, stop: f32, dt: f32) -> f32 {
    let dist = horizontal_distance(to, h.position);
    let d = flat(to - h.position);
    if d != Vec3::ZERO && dist > stop {
        h.facing = flat(turn_towards(h.facing, d, TURN_SPEED * dt)).normalize_or(h.facing);
        let step = (speed * dt).min(dist - stop);
        let facing = h.facing;
        h.position += facing * step;
    }
    horizontal_distance(to, h.position)
}

#[allow(clippy::too_many_arguments)]
pub fn update_human(
    time: Res<Time>,
    settings: Res<Settings>,
    tuning: Res<HumanTuning>,
    spatial: SpatialQuery,
    heads: Res<HeadMaterials>,
    game: Res<GameLoop>,
    mut events: ResMut<GameEvents>,
    player: Res<Player>,
    mut human: Single<(&mut Human, &mut Transform, &mut Visibility), Without<HumanHead>>,
    mut head: Single<(&mut Transform, &mut MeshMaterial3d<StandardMaterial>, &mut Visibility), With<HumanHead>>,
    mut gizmos: Gizmos,
) {
    let dt = time.delta_secs().min(0.05);
    let pt = &tuning.0;
    let q = AvianQuery { spatial: &spatial, filter: SpatialQueryFilter::default() };
    let (h, body_tf, body_vis) = &mut *human;
    let (head_tf, head_mat, head_vis) = &mut *head;
    let w = &player.walker;
    let playing = game.phase == Phase::Playing;

    // --- rythme de présence
    h.schedule -= dt;
    if !h.present {
        h.suspicion.update(0.0, w.position, pt, dt);
        h.last_visibility = Sight::default();
        if h.schedule <= 0.0 {
            h.present = true;
            h.leaving = false;
            h.schedule = PRESENT_TIME;
            h.position = DOOR;
            h.facing = flat(PATROL[1] - DOOR);
            h.gaze = h.facing;
            h.waypoint = 1;
        }
        **body_vis = Visibility::Hidden;
        **head_vis = Visibility::Hidden;
        return;
    }
    **body_vis = Visibility::Inherited;
    **head_vis = Visibility::Inherited;

    // --- perception
    let in_shadow = roach_in_shadow(&q, w);
    h.in_shadow = in_shadow;
    let eye = h.position + Vec3::Y * EYE_HEIGHT;
    let target = Target {
        position: w.position,
        up: w.up,
        speed: w.velocity.length(),
        light: if in_shadow { pt.shadow_light } else { 1.0 },
        body_radius: ROACH_RADIUS,
    };
    let vis = visibility(&Observer { eye, gaze: h.gaze }, &target, pt, &q);
    h.last_visibility = vis;
    h.suspicion.update(if playing { vis.value } else { 0.0 }, w.position, pt, dt);
    let awareness = h.suspicion.awareness(pt);
    let detected = awareness == Awareness::Detected;
    if detected && !h.was_detected && playing {
        events.detected = true;
    }
    h.was_detected = detected;

    // --- comportement
    h.sweep_time += dt;
    if h.schedule <= 0.0 && awareness == Awareness::Calm {
        h.leaving = true;
    }
    let mut desired_gaze;
    match awareness {
        Awareness::Calm => {
            let sweep = SWEEP_ANGLE * (h.sweep_time * TAU / SWEEP_PERIOD).sin();
            let ahead = Quat::from_rotation_y(sweep) * h.facing;
            // regard vers le bas devant soi (là où courent les cafards), avec balayage
            desired_gaze = (ahead * 0.8 + Vec3::NEG_Y * 0.6).normalize();
            if h.leaving {
                if walk_towards(h, DOOR, WALK_SPEED, 0.0, dt) < 5.0 {
                    h.present = false;
                    h.schedule = AWAY_TIME;
                }
            } else {
                let wp = PATROL[h.waypoint];
                if walk_towards(h, wp, WALK_SPEED, 0.0, dt) < 10.0 {
                    h.waypoint = (h.waypoint + 1) % PATROL.len();
                }
            }
        }
        Awareness::Notice => {
            let at = h.suspicion.last_seen.unwrap_or(w.position);
            desired_gaze = (at - eye).normalize();
            let g = flat(desired_gaze);
            if g != Vec3::ZERO {
                h.facing = flat(turn_towards(h.facing, g, TURN_SPEED * dt)).normalize_or(h.facing);
            }
        }
        Awareness::Search => {
            let at = h.suspicion.last_seen.unwrap_or(w.position);
            desired_gaze = (at - eye).normalize();
            walk_towards(h, at, SEARCH_SPEED, BODY_RADIUS, dt);
        }
        Awareness::Detected => {
            desired_gaze = (w.position - eye).normalize();
            walk_towards(h, w.position, CHASE_SPEED, BODY_RADIUS * 0.5, dt);
        }
    }
    if desired_gaze.is_nan() {
        desired_gaze = h.facing;
    }
    h.gaze = turn_towards(h.gaze, desired_gaze, TURN_SPEED * 1.5 * dt);

    // --- écrasement : cafard au sol, suspicion ≥ « cherche », sous un pied
    let on_floor = w.grounded && w.up.y > 0.7 && w.position.y < 3.0 * ROACH_RADIUS;
    if playing
        && h.suspicion.value >= pt.search
        && on_floor
        && horizontal_distance(w.position, h.position) < FOOT_RADIUS + pt.red_zone
    {
        events.squashed = true;
        h.suspicion.value = pt.search + 10.0; // reste méfiant
        h.suspicion.last_seen = None;
    }

    // --- visuel
    body_tf.translation = h.position;
    body_tf.rotation = Quat::from_rotation_arc(Vec3::NEG_Z, h.facing);
    head_tf.translation = h.position + Vec3::Y * EYE_HEIGHT;
    head_tf.look_to(h.gaze, Vec3::Y);
    head_mat.0 = match awareness {
        Awareness::Calm => heads.calm.clone(),
        Awareness::Notice => heads.notice.clone(),
        Awareness::Search => heads.search.clone(),
        Awareness::Detected => heads.detected.clone(),
    };

    if settings.debug {
        let col = if vis.value > 0.0 { Color::srgb(1.0, 0.2, 0.2) } else { Color::srgb(0.6, 0.6, 0.6) };
        gizmos.line(eye, w.position, col.with_alpha(0.5));
        let half = pt.cone_focus * 0.5;
        let right = h.gaze.cross(Vec3::Y).normalize_or(Vec3::X);
        let up = right.cross(h.gaze).normalize_or(Vec3::Y);
        for a in [right, -right, up, -up] {
            let d = Quat::from_axis_angle(a.cross(h.gaze).normalize_or(Vec3::Y), half) * h.gaze;
            gizmos.line(eye, eye + d * pt.range_max, Color::srgb(1.0, 0.9, 0.3).with_alpha(0.4));
        }
        gizmos.circle(
            Isometry3d::new(Vec3::new(h.position.x, 0.2, h.position.z), Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
            FOOT_RADIUS + pt.red_zone,
            Color::srgb(1.0, 0.1, 0.1),
        );
    }
}
