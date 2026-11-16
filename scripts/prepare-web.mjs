import {existsSync,cpSync,mkdirSync,rmSync} from 'node:fs';
// Godot est LE produit. L'export Godot est servi directement à la racine.
// L'ancien tableau de bord demeure accessible à /atelier comme outil secondaire.
rmSync('public',{recursive:true,force:true});
mkdirSync('public',{recursive:true});
if(!existsSync('docs/index.html'))throw new Error('Export Web Godot manquant. Publier le jeu est obligatoire.');
cpSync('docs','public',{recursive:true,force:true});
mkdirSync('public/atelier',{recursive:true});
cpSync('web','public/atelier',{recursive:true,force:true});
console.log('Jeu Godot 2D prêt à la racine du domaine.');
