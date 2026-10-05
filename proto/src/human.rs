//! Humain de test : patrouille, regard, perception et suspicion (docs/specs/perception.md §B).
//!
//! Calme → patrouille en balayant du regard ; Remarque (≥ 30) → s'arrête et regarde la dernière position vue ;
//! Cherche (≥ 60) → marche vers elle ; Détecté (100) → vient écraser le cafard s'il est au sol (zone rouge).
//! L'humain n'a pas de collider : le cafard ne peut pas (encore) lui grimper dessus.

use std::f32::consts::TAU;

use avian3d::prelude::*;
use bevy::prelude::*;

use cockroach_proto::perception::{Awareness, Observer, PerceptionTuning, Suspicion, Target, Visibility as Sight, visibility};
use cockroach_proto::query::SurfaceQuery;
use cockroach_proto::walker::Walker;

use crate::{AvianQuery, Player, ROACH_RADIUS, SPAWN, SUN_POSITION, Settings};

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
    sweep_time: f32,
    /// Affiche « Écrasé ! » pendant quelques secondes.
    pub squash_message: f32,
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
    let start = PATROL[0];
    let facing = (PATROL[1] - PATROL[0]).normalize();
    commands
        .spawn((
            Human {
                position: start,
                facing,
                gaze: facing,
                waypoint: 1,
                suspicion: Suspicion::default(),
                last_visibility: Sight::default(),
                in_shadow: false,
                sweep_time: 0.0,
                squash_message: 0.0,
            },
            Transform::from_translation(start),
            Visibility::default(),
        ))
        .with_children(|p| {
            // Jambes, torse, tête : repère local +Y haut, -Z avant.
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

/// Le cafard est-il à l'ombre ? Rayon vers le soleil de la scène.
fn roach_in_shadow(q: &impl SurfaceQuery, w: &Walker) -> bool {
    let origin = w.position + w.up * ROACH_RADIUS * 0.6;
    let to_sun = (SUN_POSITION - origin).normalize();
    q.ray(origin, to_sun, 2000.0).is_some()
}

#[allow(clippy::too_many_arguments)]
pub fn update_human(
    time: Res<Time>,
    settings: Res<Settings>,
    tuning: Res<HumanTuning>,
    spatial: SpatialQuery,
    heads: Res<HeadMaterials>,
    mut player: ResMut<Player>,
    mut human: Single<(&mut Human, &mut Transform), Without<HumanHead>>,
    mut head: Single<(&mut Transform, &mut MeshMaterial3d<StandardMaterial>), With<HumanHead>>,
    mut gizmos: Gizmos,
) {
    let dt = time.delta_secs().min(0.05);
    let pt = &tuning.0;
    let q = AvianQuery { spatial: &spatial, filter: SpatialQueryFilter::default() };
    let (h, body_tf) = &mut *human;
    let w = player.walker.clone();

    // --- perception
    let in_shadow = roach_in_shadow(&q, &w);
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
    h.suspicion.update(vis.value, w.position, pt, dt);
    let awareness = h.suspicion.awareness(pt);

    // --- comportement
    h.sweep_time += dt;
    let mut desired_gaze;
    let mut move_to: Option<(Vec3, f32)> = None;
    match awareness {
        Awareness::Calm => {
            let wp = PATROL[h.waypoint];
            if flat(wp - h.position) == Vec3::ZERO || (wp - h.position).length() < 10.0 {
                h.waypoint = (h.waypoint + 1) % PATROL.len();
            }
            move_to = Some((PATROL[h.waypoint], WALK_SPEED));
            // regard vers le bas devant soi (là où marchent les cafards), avec balayage
            let sweep = SWEEP_ANGLE * (h.sweep_time * TAU / SWEEP_PERIOD).sin();
            let ahead = Quat::from_rotation_y(sweep) * h.facing;
            desired_gaze = (ahead * 0.8 + Vec3::NEG_Y * 0.6).normalize();
        }
        Awareness::Notice => {
            let at = h.suspicion.last_seen.unwrap_or(w.position);
            desired_gaze = (at - eye).normalize();
        }
        Awareness::Search => {
            let at = h.suspicion.last_seen.unwrap_or(w.position);
            desired_gaze = (at - eye).normalize();
            move_to = Some((at, SEARCH_SPEED));
        }
        Awareness::Detected => {
            desired_gaze = (w.position - eye).normalize();
            move_to = Some((w.position, CHASE_SPEED));
        }
    }
    if let Some((to, speed)) = move_to {
        let d = flat(to - h.position);
        let dist = Vec3::new(to.x - h.position.x, 0.0, to.z - h.position.z).length();
        let stop = if awareness == Awareness::Calm { 0.0 } else { BODY_RADIUS };
        if d != Vec3::ZERO && dist > stop {
            h.facing = flat(turn_towards(h.facing, d, TURN_SPEED * dt)).normalize_or(h.facing);
            let step = (speed * dt).min(dist - stop);
            let facing = h.facing;
            h.position += facing * step;
        }
    } else if awareness != Awareness::Calm {
        // à l'arrêt, le corps se tourne vers ce qu'il regarde
        let g = flat(desired_gaze);
        if g != Vec3::ZERO {
            h.facing = flat(turn_towards(h.facing, g, TURN_SPEED * dt)).normalize_or(h.facing);
        }
    }
    if desired_gaze.is_nan() {
        desired_gaze = h.facing;
    }
    h.gaze = turn_towards(h.gaze, desired_gaze, TURN_SPEED * 1.5 * dt);

    // --- écrasement : cafard au sol, détecté, sous un pied
    h.squash_message = (h.squash_message - dt).max(0.0);
    let horizontal = Vec3::new(w.position.x - h.position.x, 0.0, w.position.z - h.position.z).length();
    let on_floor = w.grounded && w.up.y > 0.7 && w.position.y < 3.0 * ROACH_RADIUS;
    if h.suspicion.value >= pt.search && on_floor && horizontal < FOOT_RADIUS + pt.red_zone {
        player.walker = Walker::new(SPAWN, Vec3::NEG_Z);
        h.suspicion.value = pt.search + 10.0; // reste méfiant
        h.suspicion.last_seen = None;
        h.squash_message = 2.5;
    }

    // --- visuel
    body_tf.translation = h.position;
    body_tf.rotation = Quat::from_rotation_arc(Vec3::NEG_Z, h.facing);
    let (head_tf, head_mat) = &mut *head;
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
        for (a, b) in [(right, half), (-right, half), (up, half), (-up, half)] {
            let d = Quat::from_axis_angle(a.cross(h.gaze).normalize_or(Vec3::Y), b) * h.gaze;
            gizmos.line(eye, eye + d * pt.range_max, Color::srgb(1.0, 0.9, 0.3).with_alpha(0.4));
        }
        gizmos.circle(
            Isometry3d::new(Vec3::new(h.position.x, 0.2, h.position.z), Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
            FOOT_RADIUS + pt.red_zone,
            Color::srgb(1.0, 0.1, 0.1),
        );
    }
}
