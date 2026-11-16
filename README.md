# ErgoLab, cuisine scolaire (Godot 4)

Jeu bac à sable en 2D, développé dans Godot 4.4 (GDScript). Le plan architectural du TP de simulation en distanciel (page 5) a servi à reconstruire un environnement visuel : sols, salles, murs et accès. La bibliothèque de matériels s'inspire de la page 6.

**Important :** la restitution ludique des contours et les deux seuils sont approximatifs. Le plan coté complet est nécessaire pour les valider ; le calque d'architecte peut être affiché avec **F2**. Les équipements préplacés dans le scénario « Exemple à modifier » constituent un **exemple pédagogique**, pas une implantation validée par l'architecte.

## Jouer

- **ZQSD**, WASD ou flèches : déplacer son personnage ; clic sur le sol : aller à cet endroit.
- **E** : utiliser le poste proche (préparer, cuisiner, pousser le chariot, laver, etc.), puis E pour arrêter.
- **Matériel** : afficher/masquer la bibliothèque ; cliquer sur un objet pour le placer, glisser pour le déplacer.
- **R** : tourner l'objet sélectionné ; **Suppr** : le retirer.
- **Molette** : zoom au niveau du pointeur ; **bouton central glissé** : déplacer la caméra.
- **Cuisine / Plan entier** : changer d'échelle ; **F2** : voir le document original par transparence.
- **+ Salle** : créer une session commune ; donner le lien aux autres pour rejoindre avec leur pseudonyme.

Pas de progression, de score ni de mission obligatoire. Les participants sont libres d'explorer une situation, de discuter les obstacles, puis de réaménager la cuisine pendant la séance.

## Organisation technique

- Godot 4.4.1 (moteur de jeu, rendu, collisions, personnages, interface native).
- GDScript, `main.tscn` → `scripts/sandbox_game.gd`, aucune interface HTML substitutive à la racine.
- Vercel sert l'export Godot Web et les fonctions HTTP/WebSocket.
- Neon PostgreSQL conserve les salles, avatars, scénarios et événements via l'API.
- GitHub Actions compile le projet Godot Web et publie la version compilée dans `docs/`, reprise par Vercel.

Le modèle d'animation permet la simulation participative ; les indicateurs de distance et de présence ne constituent pas une évaluation biomécanique ou sanitaire validée.

## Développement

```
node --test tests/*.test.js
# Ouvrir project.godot avec Godot 4.4 ou exporter via GitHub Actions
```
