import {existsSync,cpSync,mkdirSync,rmSync} from 'node:fs';
// Build Vercel: tableau de bord de classe en accueil, moteur Godot dans /simulateur.
mkdirSync('public',{recursive:true});
cpSync('web','public',{recursive:true,force:true});
cpSync('assets','public/assets',{recursive:true,force:true});
if (existsSync('docs/index.html')){
 mkdirSync('public/simulateur',{recursive:true});
 cpSync('docs','public/simulateur',{recursive:true,force:true});
} else console.warn('Godot export missing: dashboard remains available, /simulateur disabled.');
console.log('ErgoLab dashboard + assets copied.');
