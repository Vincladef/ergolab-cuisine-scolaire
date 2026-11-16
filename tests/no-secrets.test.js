import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('database credentials must not appear in frontend sources',()=>{
 const sources=['scripts/network_room.gd','scripts/main.gd','scripts/map_canvas.gd'];
 for(const f of sources){
   const text=readFileSync(new URL('../'+f,import.meta.url),'utf8');
   assert.ok(!/postgres(?:ql)?:\/\//i.test(text),f+' contient une URL SQL');
 }
});
