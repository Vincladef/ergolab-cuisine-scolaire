import {existsSync,cpSync,mkdirSync,writeFileSync} from 'node:fs';
// Build output must be committed by GitHub Actions before Vercel deploys.
if(!existsSync('docs/index.html'))throw new Error('Export Godot absent : le workflow GitHub Actions doit produire docs/index.html');
mkdirSync('public',{recursive:true});
cpSync('docs','public',{recursive:true,force:true});
console.log('Export Godot copié dans public/');
