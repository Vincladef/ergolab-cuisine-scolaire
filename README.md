# ErgoLab | Cuisine scolaire | Simulation collaborative 2D

Prototype **Godot 4 (GDScript) + WebSocket + Neon PostgreSQL + Vercel**. La maquette se fonde sur les pages 5 (plan) et 6 (équipements) de `TP simulation en distanciel - consigne.pdf`.

## Ce qui a été développé

- Plan issu du PDF, calibration approximative de 14,20 m = 608 pixels à contrôler avec la source architecturale ; le document est un raster, et non un fichier CAD coté exhaustivement.
- Bibliothèque de 14 types de matériel, déplacements, rotations, duplication, configurations A/B, observations et grille métrique.
- Salles isolées créées via un code aléatoire à 12 caractères, invitations sous `?s=CODE`, aucun compte à créer.
- Chaque participant choisit un pseudonyme et une couleur d'avatar. Il le déplace au clavier ou à la souris ; les autres voient sa position via WebSocket.
- Actions contextualisées : préparation, cuisson, charge, pousse d'un chariot, plonge, service, nettoyage, livraison, attente. **La plupart sont des annotations d'activité ; seule la pousse de chariot modifie sa position.**
- Collision simplifiée avec les équipements et les autres agents ; vitesse plus lente avec charge ou chariot ; tracés enregistrés en base.
- L'animateur de la salle peut mettre en pause et verrouiller les aménagements. Les autres membres peuvent modifier l'agencement lorsque celui-ci est déverrouillé.
- Reconnexion automatique, sauvegarde des identités de plusieurs salles dans `user://`, états et événements dans Neon.
- Diffusion de mouvements entre les instances Vercel au moyen du journal d'événements en base consulté à intervalle court ; les messages prennent généralement moins d'une seconde mais ce n'est pas une garantie de latence.

## Architecture

```text
Godot Web (GDScript)
    ├─ POST /api/session : créer, rejoindre, reprendre sa place
    └─ WSS /api/ws : mouvements, actions, scénarios, contrôle animateur
                       └─ Neon PostgreSQL
                           rooms / room_participants / room_events
```

Le serveur garde les décisions d'autorisation. Les tokens d'identité, envoyés dans le corps de requêtes privées, ne sont **jamais publiés dans le dépôt GitHub**. Les liens de salles ne confèrent pas les droits d'animateur.

## Installation

1. Créer une base Neon dédiée et appliquer `sql/001_initial.sql` (déjà fait dans le projet Neon `calm-dream-89015446`).
2. Définir `DATABASE_URL` dans les variables chiffrées Vercel, pour les environnements voulus (déjà configuré dans le projet Vercel `ergolab-cuisine-scolaire`).
3. Connecter le dépôt GitHub `Vincladef/ergolab-cuisine-scolaire` à Vercel. **Attention : l'association GitHub → Vercel doit être autorisée dans Vercel**.
4. Publier les sources sur la branche `main`. GitHub Actions installe Godot 4.4.1, teste les fichiers serveur et produit un export Godot Web dans `docs/`, qu'il commite sur `main`.
5. Le déploiement Vercel, lancé après ce commit, exécute `npm run build`, qui copie `docs/` dans `public/`. Les Functions `api/session.js` et `api/ws.js` sont déployées côté serveur.
6. Accéder au site public, créer une salle puis inviter les élèves et le professeur grâce au lien.

## Tests

```sh
npm test
npm run check
```

La compilation et l'interaction Godot doivent également être testées dans GitHub Actions puis dans un navigateur. Les tests Node ne suffisent pas à certifier l'ensemble de l'application.

## Limites ergonomiques importantes

- Les murs et passages sont visibles sur la **rasterisation du plan**, mais il n'y a **pas encore de collision géométrique fidèle aux murs/portes**. Les collisions portent sur les équipements et les avatars. Ne pas utiliser pour valider les dégagements réglementaires.
- Les dimensions de meubles proviennent d'une extraction graphique indicative ; confirmer sur les cotes et références des équipements.
- Les mesures de distance et d'occupation ne diagnostiquent ni TMS ni charge mentale. Elles soutiennent l'entretien et la simulation participative.
- Les rôles et interactions sont une base d'atelier, pas une simulation complète des gestes professionnels.
- La synchronisation multi-instances utilise une interrogation du journal Neon. À forte charge, préférer un bus de publication dédié (Redis/Upstash), pour limiter la sollicitation de la base.
- Les mouvements de chariot reposent sur une logique simplifiée. Des tests utilisateurs et un durcissement du protocole restent nécessaires avant un usage public prolongé.
