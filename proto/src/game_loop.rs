//! Boucle de jeu (Bible §3) : SORTIR → EXPLORER → DÉTECTER LE DANGER → FUIR → SE CACHER
//! → RÉCUPÉRER UNE RESSOURCE → RETOURNER AU REFUGE, avec escalade de menace (Bible §1).
//!
//! Refuge sous le meuble bas ; miettes à ramener une par une (le cafard est ralenti en portant) ; l'humain
//! entre et sort de la cuisine ; chaque détection fait monter la menace (pièges collants, vigilance accrue,
//! puis désinsectiseur = partie perdue). Trois vies : écrasé = retour au refuge sans la miette.

use bevy::prelude::*;

use cockroach_proto::walker::Walker;

use crate::human::{Human, HumanTuning, reset_human};
use crate::{Player, PlayerInput, ROACH_RADIUS, SPAWN};

/// Refuge : dessous du meuble bas (surélevé de 4 cm).
pub const REFUGE_MIN: Vec3 = Vec3::new(-193.0, -1.0, -148.0);
pub const REFUGE_MAX: Vec3 = Vec3::new(-47.0, 4.0, -106.0);
const CRUMBS_TO_WIN: u32 = 10;
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
            Phase::Won => format!("VICTOIRE ! {} miettes : la nichee grandit.\nR / Start : rejouer", gl.delivered),
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
        let n = gl.delivered;
        gl.say(format!("Miette rapportee ({n}/{CRUMBS_TO_WIN})"));
        if n >= CRUMBS_TO_WIN {
            gl.phase = Phase::Won;
        }
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

/// Lignes de HUD de la boucle de jeu (objectif, vies, menace, humain, antennes).
pub fn hud_lines(gl: &GameLoop, human: Option<&Human>, roach: Vec3) -> String {
    let mut s = format!(
        "Miettes : {}/{}{}   Vies : {}   Menace : {}/4{}\n",
        gl.delivered,
        CRUMBS_TO_WIN,
        if gl.carrying { " (en porte une)" } else { "" },
        gl.lives,
        gl.threat,
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
