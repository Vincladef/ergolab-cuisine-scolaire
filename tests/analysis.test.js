import {test} from 'node:test';import {strict as assert} from 'node:assert';
import {analyzeEvents,sanitizeScript,sanitizeCriteria} from '../server/analysis.js';
test('script chronologique valide et garde les limites',()=>{
 let s=sanitizeScript([{id:'2',at:120,title:'Cuisson'},{id:'1',at:30,title:'Livraison'}]);assert.equal(s[0].title,'Livraison');
 assert.throws(()=>sanitizeScript([{at:-1,title:'Impossible'}]));
 assert.throws(()=>sanitizeScript([{id:'A',at:3,title:'oui'},{id:'A',at:4,title:'oui'}]));
 assert.deepEqual(sanitizeCriteria(['Circulation','  ']),['Circulation']);
});
test('distance et temps attente issus des traces, sans pourcentage TMS',()=>{
 const base='2026-11-16T09:00:';
 const e=[
  {seq:1,kind:'move',payload:{id:'a',x:40,y:100},created_at:base+'00Z'},
  {seq:2,kind:'move',payload:{id:'a',x:82.82,y:100},created_at:base+'01Z'},
  {seq:3,kind:'interaction',payload:{id:'a',action:'attendre'},created_at:base+'02Z'},
  {seq:4,kind:'interaction',payload:{id:'a',action:'préparer'},created_at:base+'07Z'},
  {seq:5,kind:'script_step',payload:{step:{title:'Livraison'}},created_at:base+'08Z'}];
 const m=analyzeEvents(e); assert.equal(m.distance_m,1);assert.equal(m.wait_s,5);assert.equal(m.script_steps_triggered,1);
 assert.match(m.method,/pas de diagnostic TMS/);
});
test('estimation de proximite temporelle',()=>{
 const e=[{seq:1,kind:'move',payload:{id:'a',x:100,y:200},created_at:'2026-11-16T09:00:00Z'},
 {seq:2,kind:'move',payload:{id:'b',x:110,y:205},created_at:'2026-11-16T09:00:01Z'}];
 assert.equal(analyzeEvents(e).crossings_estimated,1);
});
