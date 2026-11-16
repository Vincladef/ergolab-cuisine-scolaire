# ErgoLab | Cuisine scolaire : atelier ergonomique collaboratif

Application publiée sur Vercel, avec moteur **Godot 4.4.1 / GDScript** disponible dans `/simulateur/index.html` et tableau de bord de classe en accueil (`/`). Les étudiants peuvent rejoindre une salle sans compte, créer un avatar et jouer une situation de travail depuis une URL commune.

## Fonctions

- **Séance 1 : repères**. Définition des contraintes de travail et exigences de conception, conservées dans Neon.
- **Séances 2 et 3 : aménagement**. Fond du plan de la future cuisine, PDF p.5, et catalogue d'équipements, p.6. Placement, rotation, duplication des variantes, notes et édition partagée.
- **Séance 4 : simulation**. Pseudonyme, avatar, clavier ZQSD/WASD/flèches, actions au poste le plus proche, salle partagée, animateur (pause, verrouillage, lancement de séquences et déclenchement de scripts chronologiques).
- **Analyse**. Journal des événements, observations humaines catégorisées (manutention, posture, accident, coordination, flux, obstacles et circulation), métriques exploratoires (distance, attente déclarée, proximités temporelles), comparatif par séquence et rapport PDF avec visuels de tous les scénarios.
- **Collaboration**. WebSocket avec journal d'événements partagé via Neon ; secours HTTP lorsque le WebSocket est indisponible. Identité anonyme conservée localement pour retrouver son avatar après actualisation.

## Architecture

- `project.godot`, `main.tscn`, `scripts/` : projet Godot, export Web sur `/simulateur/`.
- `web/` : interface native HTML/CSS/JavaScript en accueil, avec visualisation métrique 2D du même plan, jeu d'avatars et pilotage de l'atelier.
- `api/session.js`, `api/ws.js`, `api/command.js`, `api/workshop.js`, `api/report.js` : routes Vercel.
- `server/model.js`, `server/workshop.js`, `server/analysis.js` : règles, persistance et calculs.
- `sql/001_initial.sql`, `sql/002_workshop.sql` : schéma de base.
- `.github/workflows/build-web.yml` : tests Node, import Godot headless, export Web dans `docs/`, commit des artefacts compilés. Vercel publie `public/` produit par `npm run build`.

## Publication

1. Associer le dépôt à un projet Vercel, à la racine du dépôt.
2. Définir `DATABASE_URL` uniquement dans les variables sécurisées du projet Vercel.
3. Appliquer les migrations SQL sur une base dédiée.
4. Vercel installe les dépendances et exécute `npm run build`, qui copie le tableau de bord, les planches d'équipements et l'export Web Godot.
5. Chaque push sur `main` déclenche les tests et l'export Godot dans GitHub Actions. Le workflow actualise `docs/` et Vercel republie la compilation.

## Tests

- `npm test` : validation du script, données de plan, métriques, collisions d'équipements et absence de credentials dans le client.
- `npm run check` : vérification syntaxique du code JavaScript.
- Validation manuelle en production : deux navigateurs indépendants, création/reconnexion, enregistrement des scripts, déplacements partagés, annotations, duplication de scénario, téléchargement PDF et vérification visuelle sur desktop/mobile.

## Précautions ergonomiques

La scène est un **support de simulation participative**, pas un calculateur de pénibilité. La calibration `42,82 px/m` est une approximation issue de la cote de 14,20 m du PDF p.5. Les volumes, portes, dégagements et cheminements doivent être confirmés sur les documents cotés de l'architecte. Les proximités spatio-temporelles ne constituent pas une détection validée de collisions ni un diagnostic de TMS. Les temps d'attente proviennent des actions « attendre » déclarées. Les observations des agents doivent primer sur les chiffres.

## Limites restant à valider

- Relevé métrique exact des parois, passages, sens des portes, capacités des équipements ; le fond raster n'offre pas à lui seul une géométrie physique fiable.
- Validation ergonomique des manutentions et postures en situation réelle.
- Tests de charge avec l'effectif d'une classe entière et vérification de tous les navigateurs (Chromium testé ; Firefox et Safari restent à tester).
- Le moteur Godot autonome et l'interface web sont deux clients de la même salle ; l'interface web sert de console principale d'atelier.
