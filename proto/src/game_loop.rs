//! Boucle de jeu (Bible §3) : SORTIR → EXPLORER → DÉTECTER LE DANGER → FUIR → SE CACHER
//! → RÉCUPÉRER UNE RESSOURCE → RETOURNER AU REFUGE, avec escalade de menace (Bible §1).
//!
//! Refuge sous le meuble bas ; miettes à ramener une par une (le cafard est ralenti en portant) ; l'humain
//! entre et sort de la cuisine ; chaque détection fait monter la menace (pièges collants, vigilance accrue,
//! puis désinsectiseur = partie perdue). Trois vies : écrasé = retour au refuge sans la miette.

use bevy::prelude::*;

use cockroach_proto::colony::{Colony, ColonyTuning};
use cockroach_proto::walker::Walker;

use crate::human::{Human, HumanTuning, reset_human};
use crate::{Player, PlayerInput, ROACH_RADIUS, SPAWN};

/// Refuge : dessous du meuble bas (surélevé de 4 cm).
pub const REFUGE_MIN: Vec3 = Vec3::new(-193.0, -1.0, -148.0);
pub const REFUGE_MAX: Vec3 = Vec3::new(-47.0, 4.0, -106.0);
const ACTIVE_CRUMBS: usize = 5;
const PICK_RADIUS: f32 = 2.5 * ROACH_RADIUS;
/// Ralentissement en portant une miette (Les Fourmis : ResourcesCarryingUnitSpeedRatio).
pub const CARRY_SPEED_FACTOR: f32 = 0.8;
const LIVES: u32 = 3;
const STUCK_TIME: f32 = 3.0;
const BASE_GAIN: f32 = 100.0 / 1.5;
const MESSAGE_TIME: f32 = 3.5;

/// Emplacements possibles des miettes (dessus des surfaces + rayon de la miette).
const CRUMB_SPOTS: [Vec3; 16] = [
    Vec3::new(0.0, 0.8, 60.0),
    Vec3::new(80.0, 0.8, 120.0),
    Vec3::new(-160.0, 0.8, 80.0),
    Vec3::new(170.0, 0.8, -40.0),
    Vec3::new(-30.0, 0.8, -40.0),
    Vec3::new(60.0, 0.8, -100.0),
    Vec3::new(-80.0, 0.8, 120.0),
    Vec3::new(150.0, 0.8, 130.0),
    Vec3::new(-40.0, 77.8, -60.0),
    Vec3::new(30.0, 77.8, -20.0),
    Vec3::new(-160.0, 90.8, -120.0),
    Vec3::new(-80.0, 90.8, -110.0),
    Vec3::new(160.0, 180.8, -115.0),
    Vec3::new(-70.0, 12.8, 70.0),
    Vec3::new(-30.0, 12.8, 30.0),
    Vec3::new(100.0, 0.8, 20.0),
];
/// Pièges collants (niveau de menace 2) : sur les trajets du sol.
const TRAP_SPOTS: [Vec3; 4] =
    [Vec3::new(-40.0, 0.1, 40.0), Vec3::new(60.0, 0.1, 70.0), Vec3::new(-150.0, 0.1, -60.0), Vec3::new(120.0, 0.1, -20.0)];
const TRAP_HALF: f32 = 5.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Phase {
    Playing,
    Won,
    Lost(&'static str),
}

#[derive(Resource)]
pub struct GameLoop {
    pub delivered: u32,
    pub colony: Colony,
    pub colony_tuning: ColonyTuning,
    pub carrying: bool,
    pub lives: u32,
    pub threat: u32,
    pub phase: Phase,
    pub message: String,
    pub message_time: f32,
    pub stuck: f32,
    pub in_refuge: bool,
    pub speed_factor: f32,
    seed: u32,
    trap_cooldown: f32,
}

impl Default for GameLoop {
    fn default() -> Self {
        Self {
            delivered: 0,
            colony: Colony::default(),
            colony_tuning: ColonyTuning::default(),
            carrying: false,
            lives: LIVES,
            threat: 0,
            phase: Phase::Playing,
            message: "Sors du refuge et ramene des miettes. Evite le regard de l'humain.".into(),
            message_time: 6.0,
            stuck: 0.0,
            in_refuge: true,
            speed_factor: 1.0,
            seed: 12345,
            trap_cooldown: 0.0,
        }
    }
}

impl GameLoop {
    fn say(&mut self, text: impl Into<String>) {
        self.message = text.into();
        self.message_time = MESSAGE_TIME;
    }

    fn next_random(&mut self) -> u32 {
        // xorshift : pas besoin de crate de hasard pour un prototype
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 17;
        self.seed ^= self.seed << 5;
        self.seed
    }
}

/// Événements produits par l'humain, consommés ici.
#[derive(Resource, Default)]
pub struct GameEvents {
    pub squashed: bool,
    pub detected: bool,
}

#[derive(Component)]
pub struct Crumb {
    spot: usize,
}

#[derive(Component)]
pub struct CarriedCrumb;

#[derive(Component)]
pub struct Trap;

#[derive(Component)]
pub struct BigMessage;

#[derive(Resource)]
pub struct GameAssets {
    member_mesh: Handle<Mesh>,
    adult_mat: Handle<StandardMaterial>,
    nymph_mat: Handle<StandardMaterial>,
    ootheca_mesh: Handle<Mesh>,
    ootheca_mat: Handle<StandardMaterial>,
    crumb_mesh: Handle<Mesh>,
    crumb_mat: Handle<StandardMaterial>,
    trap_mesh: Handle<Mesh>,
    trap_mat: Handle<StandardMaterial>,
}

pub struct GameLoopPlugin;

impl Plugin for GameLoopPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GameLoop>().init_resource::<GameEvents>().add_systems(Startup, setup);
    }
}

pub fn in_refuge(p: Vec3) -> bool {
    p.cmpge(REFUGE_MIN).all() && p.cmple(REFUGE_MAX).all()
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let assets = GameAssets {
        member_mesh: meshes.add(Sphere::new(1.0)),
        adult_mat: materials.add(StandardMaterial {
            base_color: Color::srgb(0.26, 0.13, 0.05),
            perceptual_roughness: 0.35,
            ..default()
        }),
        // les nymphes qui viennent de muer sont pâles
        nymph_mat: materials.add(StandardMaterial { base_color: Color::srgb(0.75, 0.62, 0.45), ..default() }),
        ootheca_mesh: meshes.add(Capsule3d::new(0.35, 0.9)),
        ootheca_mat: materials.add(StandardMaterial { base_color: Color::srgb(0.35, 0.18, 0.08), ..default() }),
        crumb_mesh: meshes.add(Sphere::new(0.8)),
        crumb_mat: materials.add(StandardMaterial {
            base_color: Color::srgb(0.95, 0.75, 0.35),
            emissive: LinearRgba::rgb(0.25, 0.15, 0.02),
            perceptual_roughness: 0.9,
            ..default()
        }),
        trap_mesh: meshes.add(Cuboid::new(TRAP_HALF * 2.0, 0.2, TRAP_HALF * 2.0)),
        trap_mat: materials.add(StandardMaterial { base_color: Color::srgb(0.85, 0.80, 0.30), ..default() }),
    };
    commands.spawn((
        CarriedCrumb,
        Mesh3d(assets.crumb_mesh.clone()),
        MeshMaterial3d(assets.crumb_mat.clone()),
        Transform::default(),
        Visibility::Hidden,
    ));
    commands.spawn((
        BigMessage,
        Text::new(""),
        TextFont::from_font_size(FontSize::Px(34.0)),
        TextColor(Color::srgb(1.0, 0.85, 0.3)),
        Node { position_type: PositionType::Absolute, top: Val::Percent(40.0), left: Val::Percent(20.0), ..default() },
    ));
    let mut gl = GameLoop::default();
    spawn_crumbs(&mut commands, &assets, &mut gl, &[]);
    commands.insert_resource(gl);
    commands.insert_resource(assets);
}

fn spawn_crumbs(commands: &mut Commands, assets: &GameAssets, gl: &mut GameLoop, taken: &[usize]) {
    let mut used: Vec<usize> = taken.to_vec();
    while used.len() < ACTIVE_CRUMBS {
        let spot = (gl.next_random() as usize) % CRUMB_SPOTS.len();
        if used.contains(&spot) {
            continue;
        }
        used.push(spot);
        if !taken.contains(&spot) {
            commands.spawn((
                Crumb { spot },
                Mesh3d(assets.crumb_mesh.clone()),
                MeshMaterial3d(assets.crumb_mat.clone()),
                Transform::from_translation(CRUMB_SPOTS[spot]),
            ));
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub fn update_game(
    mut commands: Commands,
    time: Res<Time>,
    input: Res<PlayerInput>,
    assets: Res<GameAssets>,
    mut gl: ResMut<GameLoop>,
    mut events: ResMut<GameEvents>,
    mut player: ResMut<Player>,
    mut human_tuning: ResMut<HumanTuning>,
    mut humans: Query<&mut Human>,
    crumbs: Query<(Entity, &Crumb)>,
    traps: Query<Entity, With<Trap>>,
    mut carried: Single<(&mut Transform, &mut Visibility), With<CarriedCrumb>>,
    mut big: Single<&mut Text, With<BigMessage>>,
) {
    let dt = time.delta_secs().min(0.05);
    gl.message_time = (gl.message_time - dt).max(0.0);

    // --- fin de partie : R / Start pour recommencer
    if gl.phase != Phase::Playing {
        big.0 = match &gl.phase {
            Phase::Won => format!(
                "VICTOIRE ! La colonie compte {} cafards ({} miettes).\nR / Start : rejouer",
                gl.colony.population(),
                gl.delivered
            ),
            Phase::Lost(reason) => format!("PARTIE PERDUE : {reason}\nR / Start : rejouer"),
            Phase::Playing => String::new(),
        };
        if input.reset {
            for (e, _) in &crumbs {
                commands.entity(e).despawn();
            }
            for e in &traps {
                commands.entity(e).despawn();
            }
            let seed = gl.seed;
            *gl = GameLoop { seed, ..default() };
            spawn_crumbs(&mut commands, &assets, &mut gl, &[]);
            player.walker = Walker::new(SPAWN, Vec3::Z);
            human_tuning.0.gain = BASE_GAIN;
            for mut h in &mut humans {
                reset_human(&mut h);
            }
            *events = GameEvents::default();
            big.0.clear();
        }
        gl.speed_factor = 0.0;
        return;
    }
    big.0.clear();

    let w = player.walker.clone();
    gl.in_refuge = in_refuge(w.position);

    // --- ramassage / dépôt
    if !gl.carrying {
        if let Some((e, _)) = crumbs.iter().find(|(_, c)| CRUMB_SPOTS[c.spot].distance(w.position) < PICK_RADIUS) {
            commands.entity(e).despawn();
            gl.carrying = true;
            let taken: Vec<usize> = crumbs.iter().filter(|(e2, _)| *e2 != e).map(|(_, c2)| c2.spot).collect();
            spawn_crumbs(&mut commands, &assets, &mut gl, &taken);
            gl.say("Miette ! Rapporte-la au refuge (sous le meuble bas).");
        }
    } else if gl.in_refuge {
        gl.carrying = false;
        gl.delivered += 1;
        gl.colony.add_food(1.0);
        let food = gl.colony.food;
        gl.say(format!("Miette rapportee : reserve de la colonie {food:.1}"));
    }

    // --- événements de l'humain : détection (escalade) et écrasement
    if std::mem::take(&mut events.detected) {
        gl.threat += 1;
        human_tuning.0.gain = BASE_GAIN * (1.0 + 0.3 * gl.threat as f32);
        let msg = match gl.threat {
            1 => "Le proprietaire t'a vu ! (menace 1/4)",
            2 => "Il pose des pieges collants... (menace 2/4)",
            3 => "Il achete un insecticide : il te repere plus vite (menace 3/4)",
            _ => "",
        };
        if gl.threat >= 4 {
            gl.phase = Phase::Lost("il appelle le desinsectiseur");
        } else {
            gl.say(msg);
        }
        if gl.threat == 2 && traps.is_empty() {
            for p in TRAP_SPOTS {
                commands.spawn((
                    Trap,
                    Mesh3d(assets.trap_mesh.clone()),
                    MeshMaterial3d(assets.trap_mat.clone()),
                    Transform::from_translation(p),
                ));
            }
        }
    }
    if std::mem::take(&mut events.squashed) {
        gl.lives = gl.lives.saturating_sub(1);
        gl.carrying = false;
        player.walker = Walker::new(SPAWN, Vec3::Z);
        if gl.lives == 0 {
            gl.phase = Phase::Lost("ecrase trois fois");
        } else {
            let l = gl.lives;
            gl.say(format!("ECRASE ! Retour au refuge ({l} vie(s) restante(s))"));
        }
    }

    // --- vie de la colonie (Bible §1 : nourriture + abri correct = reproduction)
    let threat = gl.threat;
    let ct = gl.colony_tuning.clone();
    let ev = gl.colony.step(&ct, threat, dt);
    if ev.starved > 0 {
        gl.say("Une nymphe est morte de faim... rapporte des miettes !");
    } else if ev.hatched > 0 {
        let n = ev.hatched;
        gl.say(format!("{n} nymphe(s) viennent d'eclore !"));
    } else if ev.laid {
        gl.say("Une ootheque a ete pondue dans le refuge.");
    } else if ev.matured > 0 {
        gl.say("Une nymphe est devenue adulte.");
    }
    if gl.colony.reached_goal(&ct) {
        gl.phase = Phase::Won;
    }

    // --- pièges collants
    gl.trap_cooldown = (gl.trap_cooldown - dt).max(0.0);
    gl.stuck = (gl.stuck - dt).max(0.0);
    if !traps.is_empty() && gl.trap_cooldown <= 0.0 && w.grounded && w.up.y > 0.7 {
        let on_trap = TRAP_SPOTS.iter().any(|p| {
            (w.position.x - p.x).abs() < TRAP_HALF && (w.position.z - p.z).abs() < TRAP_HALF && w.position.y < 3.0
        });
        if on_trap {
            gl.stuck = STUCK_TIME;
            gl.trap_cooldown = STUCK_TIME + 2.0;
            gl.say("Piege collant ! Coince 3 secondes...");
        }
    }
    gl.speed_factor = if gl.stuck > 0.0 {
        0.0
    } else if gl.carrying {
        CARRY_SPEED_FACTOR
    } else {
        1.0
    };

    // --- miette portée : devant la tête
    let (tf, vis) = &mut *carried;
    if gl.carrying {
        tf.translation = w.position + w.forward * 2.0 * ROACH_RADIUS - w.up * 0.3 * ROACH_RADIUS;
        **vis = Visibility::Inherited;
    } else {
        **vis = Visibility::Hidden;
    }
}

/// Membre visible de la colonie (le joueur n'en fait pas partie) : il se promène dans le refuge.
#[derive(Component)]
pub struct ColonyMember {
    nymph: bool,
    dir: Vec3,
    turn_in: f32,
}

#[derive(Component)]
pub struct Ootheca;

const MEMBER_SPEED: f32 = 3.0; // cm/s : promenade tranquille
const MEMBER_SHAPE: Vec3 = Vec3::new(0.75, 0.38, 1.45);
/// Emplacements des oothèques, dans le coin du refuge contre le mur.
const OOTHECA_SPOTS: [Vec3; 6] = [
    Vec3::new(-185.0, 0.4, -144.0),
    Vec3::new(-182.0, 0.4, -144.0),
    Vec3::new(-179.0, 0.4, -144.0),
    Vec3::new(-185.0, 0.4, -141.0),
    Vec3::new(-182.0, 0.4, -141.0),
    Vec3::new(-179.0, 0.4, -141.0),
];

/// Pseudo-hasard déterministe dans [0, 1).
fn hash01(x: f32) -> f32 {
    (x.sin() * 43_758.547).fract().abs()
}

fn random_refuge_point(seed: f32, y: f32) -> Vec3 {
    let m = 4.0;
    Vec3::new(
        REFUGE_MIN.x + m + hash01(seed) * (REFUGE_MAX.x - REFUGE_MIN.x - 2.0 * m),
        y,
        REFUGE_MIN.z + m + hash01(seed * 1.7 + 3.1) * (REFUGE_MAX.z - REFUGE_MIN.z - 2.0 * m),
    )
}

/// Fait correspondre les cafards visibles à l'état de la colonie, et les fait se promener.
pub fn update_colony_visuals(
    mut commands: Commands,
    time: Res<Time>,
    assets: Res<GameAssets>,
    gl: Res<GameLoop>,
    mut members: Query<(Entity, &mut ColonyMember, &mut Transform), Without<Ootheca>>,
    oothecae: Query<Entity, With<Ootheca>>,
) {
    let dt = time.delta_secs().min(0.05);
    let now = time.elapsed_secs();
    let want = [(false, gl.colony.adults.saturating_sub(1) as usize), (true, gl.colony.nymphs.len())];
    for (nymph, count) in want {
        let have: Vec<Entity> = members.iter().filter(|(_, m, _)| m.nymph == nymph).map(|(e, _, _)| e).collect();
        for e in have.iter().skip(count) {
            commands.entity(*e).despawn();
        }
        for i in have.len()..count {
            let scale = if nymph { 0.5 } else { 1.0 } * ROACH_RADIUS;
            let seed = now * 13.0 + i as f32 * 7.3 + if nymph { 100.0 } else { 0.0 };
            let pos = random_refuge_point(seed, MEMBER_SHAPE.y * scale);
            commands.spawn((
                ColonyMember { nymph, dir: Vec3::X, turn_in: 0.0 },
                Mesh3d(assets.member_mesh.clone()),
                MeshMaterial3d(if nymph { assets.nymph_mat.clone() } else { assets.adult_mat.clone() }),
                Transform::from_translation(pos).with_scale(MEMBER_SHAPE * scale),
            ));
        }
    }
    let have: Vec<Entity> = oothecae.iter().collect();
    let want_o = gl.colony.oothecae.len().min(OOTHECA_SPOTS.len());
    for e in have.iter().skip(want_o) {
        commands.entity(*e).despawn();
    }
    for i in have.len()..want_o {
        commands.spawn((
            Ootheca,
            Mesh3d(assets.ootheca_mesh.clone()),
            MeshMaterial3d(assets.ootheca_mat.clone()),
            Transform::from_translation(OOTHECA_SPOTS[i]).with_rotation(Quat::from_rotation_z(std::f32::consts::FRAC_PI_2)),
        ));
    }

    // Promenade : changement de cap toutes les 1-3 s, rebond sur les bords du refuge.
    for (e, mut m, mut tf) in &mut members {
        m.turn_in -= dt;
        if m.turn_in <= 0.0 {
            let a = hash01(now * 3.1 + e.index_u32() as f32 * 0.37) * std::f32::consts::TAU;
            m.dir = Vec3::new(a.cos(), 0.0, a.sin());
            m.turn_in = 1.0 + 2.0 * hash01(now + e.index_u32() as f32);
        }
        let speed = if m.nymph { MEMBER_SPEED * 0.7 } else { MEMBER_SPEED };
        let mut p = tf.translation + m.dir * speed * dt;
        for axis in [0usize, 2] {
            let (lo, hi) = (REFUGE_MIN[axis] + 3.0, REFUGE_MAX[axis] - 3.0);
            if p[axis] < lo || p[axis] > hi {
                p[axis] = p[axis].clamp(lo, hi);
                m.dir[axis] = -m.dir[axis];
            }
        }
        tf.translation = p;
        tf.look_to(m.dir, Vec3::Y);
    }
}

/// Lignes de HUD de la boucle de jeu (objectif, vies, menace, humain, antennes).
pub fn hud_lines(gl: &GameLoop, human: Option<&Human>, roach: Vec3) -> String {
    let c = &gl.colony;
    let shelter = match gl.threat {
        0 => "calme",
        1 => "un peu derange",
        2 | 3 => "derange",
        _ => "inhabitable",
    };
    let mut s = format!(
        "Colonie : {} / {} cafards ({} adultes, {} nymphes, {} ootheque(s))   reserve : {:.1} miette(s)   abri : {}\n\
         Vies : {}   Menace : {}/4{}{}\n",
        c.population(),
        gl.colony_tuning.goal,
        c.adults,
        c.nymphs.len(),
        c.oothecae.len(),
        c.food,
        shelter,
        gl.lives,
        gl.threat,
        if gl.carrying { "   (porte une miette)" } else { "" },
        if gl.in_refuge { "   [A L'ABRI]" } else { "" },
    );
    if let Some(h) = human {
        if h.present {
            // Antennes : vibrations des pas, bandes du sonar (perception.md §B.3), R = 1 cm.
            let d = Vec3::new(roach.x - h.position.x, 0.0, roach.z - h.position.z).length();
            let r = ROACH_RADIUS;
            let band = if d < 18.0 * r {
                "TRES FORTES"
            } else if d < 54.0 * r {
                "fortes"
            } else if d < 71.0 * r {
                "moyennes"
            } else if d < 107.0 * r {
                "faibles"
            } else if d < 143.0 * r {
                "tres faibles"
            } else {
                "aucune"
            };
            s.push_str(&format!("Antennes : vibrations {band}{}\n", if h.last_visibility.value > 0.0 { "  -- IL TE REGARDE !" } else { "" }));
        } else {
            s.push_str(&format!("Humain absent : revient dans {:.0} s\n", h.schedule.max(0.0)));
        }
    }
    if gl.message_time > 0.0 {
        s.push_str(&format!(">> {}\n", gl.message));
    }
    s
}
