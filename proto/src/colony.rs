//! Colonie (Bible §1) : reproduction principalement naturelle, gestion légère.
//!
//! Les miettes rapportées alimentent une réserve de nourriture. Chaque cafard en consomme. Si la réserve et
//! l'abri le permettent, une oothèque (capsule d'œufs) est pondue ; elle éclot en nymphes, qui deviennent
//! adultes. Un abri dérangé (menace élevée) réduit les éclosions ; la famine tue des nymphes.
//! Temps compressés pour un prototype (une partie dure ~10-15 min). Valeurs = décisions de design.

#[derive(Clone, Debug)]
pub struct ColonyTuning {
    /// Miettes consommées par adulte et par seconde.
    pub adult_appetite: f32,
    /// Miettes consommées par nymphe et par seconde.
    pub nymph_appetite: f32,
    /// Réserve minimale pour pondre, et coût d'une ponte.
    pub lay_food: f32,
    /// Délai minimal entre deux pontes (s).
    pub lay_interval: f32,
    /// Durée d'incubation d'une oothèque (s).
    pub incubation: f32,
    /// Nymphes par éclosion dans un abri calme.
    pub clutch: u32,
    /// Durée pour qu'une nymphe devienne adulte (s).
    pub maturation: f32,
    /// Famine : délai à réserve vide avant la mort d'une nymphe (s).
    pub starvation_delay: f32,
    /// Taille de colonie qui gagne la partie.
    pub goal: u32,
}

impl Default for ColonyTuning {
    fn default() -> Self {
        Self {
            adult_appetite: 1.0 / 120.0,
            nymph_appetite: 1.0 / 240.0,
            lay_food: 2.0,
            lay_interval: 40.0,
            incubation: 30.0,
            clutch: 4,
            maturation: 60.0,
            starvation_delay: 20.0,
            goal: 12,
        }
    }
}

/// Événements d'une mise à jour (pour les messages du HUD).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ColonyEvents {
    pub laid: bool,
    /// Nombre de nymphes écloses.
    pub hatched: u32,
    pub matured: u32,
    pub starved: u32,
}

#[derive(Clone, Debug)]
pub struct Colony {
    /// Adultes, joueur compris.
    pub adults: u32,
    /// Âge de chaque nymphe (s).
    pub nymphs: Vec<f32>,
    /// Temps restant avant éclosion de chaque oothèque (s).
    pub oothecae: Vec<f32>,
    pub food: f32,
    since_lay: f32,
    starving: f32,
}

impl Default for Colony {
    fn default() -> Self {
        Self { adults: 1, nymphs: Vec::new(), oothecae: Vec::new(), food: 0.0, since_lay: 0.0, starving: 0.0 }
    }
}

impl Colony {
    pub fn population(&self) -> u32 {
        self.adults + self.nymphs.len() as u32
    }

    pub fn add_food(&mut self, amount: f32) {
        self.food += amount;
    }

    /// Nymphes par éclosion selon le niveau de menace (0 = abri calme ; chaque niveau en retire une).
    pub fn clutch_size(t: &ColonyTuning, threat: u32) -> u32 {
        t.clutch.saturating_sub(threat)
    }

    /// Une seconde de vie de la colonie. `threat` = niveau de menace de la maison (0-4).
    pub fn step(&mut self, t: &ColonyTuning, threat: u32, dt: f32) -> ColonyEvents {
        let mut ev = ColonyEvents::default();

        // Consommation.
        let need = (self.adults as f32 * t.adult_appetite + self.nymphs.len() as f32 * t.nymph_appetite) * dt;
        if self.food >= need {
            self.food -= need;
            self.starving = 0.0;
        } else {
            self.food = 0.0;
            self.starving += dt;
            if self.starving >= t.starvation_delay && !self.nymphs.is_empty() {
                // la plus jeune meurt en premier
                let youngest = self
                    .nymphs
                    .iter()
                    .enumerate()
                    .min_by(|a, b| a.1.total_cmp(b.1))
                    .map(|(i, _)| i)
                    .unwrap();
                self.nymphs.swap_remove(youngest);
                ev.starved += 1;
                self.starving = 0.0;
            }
        }

        // Ponte : intervalle écoulé, au moins un adulte, abri pas en alerte maximale, et la réserve couvre la
        // ponte + 60 s de repas de la colonie actuelle (on ne pond pas en affamant les nymphes).
        self.since_lay += dt;
        let reserve = (self.adults as f32 * t.adult_appetite + self.nymphs.len() as f32 * t.nymph_appetite) * 60.0;
        if self.adults > 0 && self.food >= t.lay_food + reserve && self.since_lay >= t.lay_interval && threat < 4 {
            self.food -= t.lay_food;
            self.oothecae.push(t.incubation);
            self.since_lay = 0.0;
            ev.laid = true;
        }

        // Incubation et éclosion.
        let clutch = Self::clutch_size(t, threat);
        let mut hatched_now = 0;
        self.oothecae.retain_mut(|left| {
            *left -= dt;
            if *left <= 0.0 {
                hatched_now += 1;
                false
            } else {
                true
            }
        });
        for _ in 0..hatched_now {
            self.nymphs.extend(std::iter::repeat_n(0.0, clutch as usize));
            ev.hatched += clutch;
        }

        // Croissance des nymphes.
        for age in &mut self.nymphs {
            *age += dt;
        }
        let before = self.nymphs.len();
        self.nymphs.retain(|age| *age < t.maturation);
        let matured = (before - self.nymphs.len()) as u32;
        self.adults += matured;
        ev.matured = matured;
        ev
    }

    pub fn reached_goal(&self, t: &ColonyTuning) -> bool {
        self.population() >= t.goal
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(c: &mut Colony, t: &ColonyTuning, threat: u32, secs: f32) -> ColonyEvents {
        let mut total = ColonyEvents::default();
        for _ in 0..(secs as usize) {
            let e = c.step(t, threat, 1.0);
            total.laid |= e.laid;
            total.hatched += e.hatched;
            total.matured += e.matured;
            total.starved += e.starved;
        }
        total
    }

    #[test]
    fn no_food_no_babies() {
        let t = ColonyTuning::default();
        let mut c = Colony::default();
        let e = run(&mut c, &t, 0, 300.0);
        assert!(!e.laid);
        assert_eq!(c.population(), 1);
    }

    #[test]
    fn food_and_calm_shelter_grow_the_colony() {
        let t = ColonyTuning::default();
        let mut c = Colony::default();
        c.add_food(3.0);
        // ponte à 40 s, éclosion à 70 s : 4 nymphes
        let e = run(&mut c, &t, 0, 75.0);
        assert!(e.laid);
        assert_eq!(c.nymphs.len(), 4);
        // elles deviennent adultes 60 s plus tard (si elles mangent)
        c.add_food(2.0);
        run(&mut c, &t, 0, 61.0);
        assert_eq!(c.adults, 5);
        assert_eq!(c.population(), 5);
    }

    #[test]
    fn threat_reduces_clutches() {
        let t = ColonyTuning::default();
        assert_eq!(Colony::clutch_size(&t, 0), 4);
        assert_eq!(Colony::clutch_size(&t, 2), 2);
        assert_eq!(Colony::clutch_size(&t, 4), 0);
        let mut c = Colony::default();
        c.add_food(3.0);
        run(&mut c, &t, 3, 75.0);
        assert_eq!(c.nymphs.len(), 1, "abri très dérangé : une seule nymphe");
    }

    #[test]
    fn starvation_kills_nymphs() {
        let t = ColonyTuning::default();
        let mut c = Colony { nymphs: vec![10.0, 5.0, 1.0], ..Default::default() };
        let e = run(&mut c, &t, 0, 45.0);
        assert_eq!(e.starved, 2, "une nymphe toutes les 20 s de famine");
        assert_eq!(c.nymphs, vec![55.0], "la plus âgée survit le plus longtemps");
    }

    #[test]
    fn appetite_consumes_food() {
        let t = ColonyTuning::default();
        let mut c = Colony { adults: 4, ..Default::default() };
        c.add_food(1.0);
        run(&mut c, &t, 4, 30.0); // menace 4 : pas de ponte, on ne mesure que l'appétit
        assert!((c.food - 0.0).abs() < 1e-3, "4 adultes × 30 s / 120 = 1 miette : {}", c.food);
    }

    #[test]
    fn goal_is_twelve() {
        let t = ColonyTuning::default();
        let c = Colony { adults: 8, nymphs: vec![0.0; 4], ..Default::default() };
        assert!(c.reached_goal(&t));
    }
}
