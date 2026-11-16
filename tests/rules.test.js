import test from 'node:test';import assert from 'node:assert/strict';
import {sanitizeScenarios,canMoveAvatar,cleanNickname,cleanAction,validatePosition,obstacleAt} from '../server/rules.js';
test('sanitize layout and reject forged avatars',()=>{
 const scenarios=sanitizeScenarios([{name:'A',objects:[{uid:1,type:'frigo',x:980,y:420,rot:450}]}]);
 assert.equal(scenarios[0].objects[0].rot,90);
 assert.throws(()=>sanitizeScenarios([{name:'hack',objects:[{uid:2,type:'avatar',x:100,y:100,rot:0}]}]));
});
test('reject malformed positions and duplicate ids',()=>{
 assert.equal(validatePosition(200,300),true);
 assert.equal(validatePosition(200,Infinity),false);
 assert.throws(()=>sanitizeScenarios([{name:'x',objects:[{uid:1,type:'frigo',x:80,y:100,rot:0},{uid:1,type:'table',x:90,y:100,rot:0}]}]));
});
test('equipment collision',()=>{
 const sc=[{objects:[{uid:1,type:'frigo',x:500,y:350,rot:0}]}];
 assert.equal(obstacleAt(500,350,sc[0].objects),true);
 assert.equal(canMoveAvatar(500,350,sc,0),false);
 assert.equal(canMoveAvatar(600,350,sc,0),true);
});
test('nickname and actions normalized',()=>{
 assert.equal(cleanNickname('<Bob>\n'),'Bob');
 assert.equal(cleanAction('BAD ACTION'),'libre');
});
