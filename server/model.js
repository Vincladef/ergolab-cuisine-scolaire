import crypto from 'node:crypto';
import { db } from './db.js';
import {cleanColor,cleanNickname,cleanAction,sanitizeScenarios,canMoveAvatar,validatePosition,obstacleAt,EQUIPMENT} from './rules.js';
const uuid = () => crypto.randomUUID();
const randomSecret = () => crypto.randomBytes(32).toString('base64url');
const hash = token => crypto.createHash('sha256').update(String(token)).digest('hex');
const eq = (a,b) => typeof a==='string' && typeof b==='string' && a.length===b.length && crypto.timingSafeEqual(Buffer.from(a),Buffer.from(b));
export const ROOM_ID = /^[a-f0-9]{12}$/;
const sanitizeRoomId = id => (typeof id==='string' && ROOM_ID.test(id) ? id : null);
const DEFAULT_SCENARIOS = [{name:'Scénario A · à aménager',notes:'Plan de la future cuisine, PDF page 5.',objects:[]},{name:'Scénario B · variante',notes:'Comparer les trajets et la coactivité.',objects:[]}];
function publicParticipant(p){return {id:p.id,nickname:p.nickname,color:p.color,role:p.role,avatar:p.avatar,connected:new Date(p.last_seen_at).getTime()>Date.now()-30000};}
export async function snapshot(roomId){
 const sql=db(); const [r]=await sql`SELECT id,scenarios,active_index,revision,paused,locked FROM rooms WHERE id=${roomId}`;
 if(!r)return null;
 const ps=await sql`SELECT id,nickname,color,role,avatar,last_seen_at FROM room_participants WHERE room_id=${roomId} ORDER BY joined_at ASC LIMIT 150`;
 return {room:r.id,scenarios:r.scenarios,active_index:r.active_index,revision:Number(r.revision),paused:r.paused,locked:r.locked,participants:ps.map(publicParticipant)};
}
export async function createRoom(nickname,color) {
 const sql=db(); const room=crypto.randomBytes(6).toString('hex'),id=uuid(),token=randomSecret(),c=cleanColor(color);
 await sql`INSERT INTO rooms(id,scenarios) VALUES (${room}, ${JSON.stringify(DEFAULT_SCENARIOS)}::jsonb)`;
 await sql`INSERT INTO room_participants(room_id,id,secret_hash,nickname,color,role)
 VALUES (${room},${id},${hash(token)},${cleanNickname(nickname)},${c},'host')`;
 return {room,id,token,role:'host',snapshot:await snapshot(room)};
}
export async function joinRoom(room,nickname,color) {
 room=sanitizeRoomId(room); if(!room)throw new Error('Code de salle invalide');
 const sql=db();const rows=await sql`SELECT id FROM rooms WHERE id=${room}`;
 if(!rows.length)throw new Error('Cette salle n’existe pas');
 const id=uuid(),token=randomSecret();
 const [{n}]=await sql`SELECT COUNT(*)::int as n FROM room_participants WHERE room_id=${room}`;
 const avatar={x:1000+(n%5)*32,y:420+(Math.floor(n/5)%4)*36,action:'libre',trail:[]};
 await sql`INSERT INTO room_participants(room_id,id,secret_hash,nickname,color,role,avatar)
 VALUES (${room},${id},${hash(token)},${cleanNickname(nickname)},${cleanColor(color)},'participant',${JSON.stringify(avatar)}::jsonb)`;
 return {room,id,token,role:'participant',snapshot:await snapshot(room)};
}
export async function authenticate(room,id,token) {
 if(!sanitizeRoomId(room) || typeof id!=='string' || !/^[a-f0-9-]{36}$/.test(id) || typeof token!=='string' || token.length>200)return null;
 const sql=db(); const [p]=await sql`SELECT id,role,nickname,color,secret_hash FROM room_participants WHERE room_id=${room} AND id=${id}`;
 if(!p || !eq(p.secret_hash,hash(token)))return null;
 await sql`UPDATE room_participants SET last_seen_at=now() WHERE room_id=${room} AND id=${id}`;
 return {id:p.id,room,role:p.role,nickname:p.nickname,color:p.color};
}
export async function heartbeat(room,id) {
 const sql=db();
 await sql`UPDATE room_participants SET last_seen_at=now() WHERE room_id=${room} AND id=${id}`;
}
export async function markDisconnected(room,id) {
 const sql=db();
 await sql`UPDATE room_participants SET last_seen_at=now()-interval '60 seconds' WHERE room_id=${room} AND id=${id}`;
}
export async function event(room,actor,kind,payload) {
 const sql=db(); const rows=await sql`INSERT INTO room_events(room_id,actor_id,kind,payload) VALUES (${room},${actor??null},${kind},${JSON.stringify(payload)}::jsonb) RETURNING seq`;
 return {seq:Number(rows[0].seq),room,kind,payload};
}
export async function latestEventSeq(room) {
 const sql=db();const [r]=await sql`SELECT COALESCE(MAX(seq),0) AS seq FROM room_events WHERE room_id=${room}`;
 return Number(r.seq);
}
export async function eventsSince(room,seq){
 const sql=db();const rows=await sql`SELECT seq,kind,payload FROM room_events WHERE room_id=${room} AND seq>${seq} ORDER BY seq LIMIT 200`;
 return rows.map(r=>({seq:Number(r.seq),room,kind:r.kind,payload:r.payload}));
}
export async function move(room,id,data) {
 const sql=db();const [r]=await sql`SELECT paused,scenarios,active_index FROM rooms WHERE id=${room}`;
 if(!r||r.paused)throw new Error('Simulation en pause');
 const x=Number(data.x), y=Number(data.y);
 if(!canMoveAvatar(x,y,r.scenarios,r.active_index)) throw new Error('Déplacement bloqué par un obstacle');
 const [p]=await sql`SELECT avatar FROM room_participants WHERE room_id=${room} AND id=${id}`;
 if(!p)throw new Error('Avatar inconnu');
 const current=p.avatar||{};
 // The client provides the position; any implausible jump is refused except an initial spawn.
 const dx=x-Number(current.x||980),dy=y-Number(current.y||440);
 if(Math.hypot(dx,dy)>100)throw new Error('Déplacement trop important');
 const trail=Array.isArray(current.trail)?current.trail.slice(-199):[];
 if(!trail.length || Math.hypot(x-trail[trail.length-1][0],y-trail[trail.length-1][1])>12)trail.push([x,y]);
 let pushed=null;
 if(current.action==='pousser' && Number.isSafeInteger(current.target)){
   const currentRoom=await sql`SELECT revision,scenarios,active_index FROM rooms WHERE id=${room}`;
   const rc=currentRoom[0];const options=rc.scenarios;
   const equipment=options[rc.active_index].objects;
   const index=equipment.findIndex(o=>o.uid===current.target && o.type==='chariot');
   if(index>=0){
     const chariot=equipment[index];
     const cx=chariot.x+dx,cy=chariot.y+dy;
     if(!validatePosition(cx,cy)||obstacleAt(cx,cy,equipment,chariot.uid))throw new Error('Le chariot est bloqué');
     equipment[index]={...chariot,x:cx,y:cy};
     const updated=await sql`UPDATE rooms SET scenarios=${JSON.stringify(options)}::jsonb,revision=revision+1,updated_at=now()
       WHERE id=${room} AND revision=${rc.revision} RETURNING revision`;
     if(!updated.length)throw new Error('Aménagement modifié en parallèle, recommence');
     pushed={uid:chariot.uid,x:cx,y:cy,revision:Number(updated[0].revision)};
   }
 }
 const avatar={...current,x,y,trail};
 await sql`UPDATE room_participants SET avatar=${JSON.stringify(avatar)}::jsonb,last_seen_at=now() WHERE room_id=${room} AND id=${id}`;
 return event(room,id,'move',{id,x,y,trail,pushed});
}
export async function interaction(room,id,data){
 const sql=db(); const [r]=await sql`SELECT paused,scenarios,active_index FROM rooms WHERE id=${room}`;
 if(!r||r.paused)throw new Error('Simulation en pause');
 const action=cleanAction(data.action);
 const target=Number.isSafeInteger(data.target)&&data.target>0?data.target:null;
 const [p]=await sql`SELECT avatar FROM room_participants WHERE room_id=${room} AND id=${id}`;
 if(!p)throw new Error('Avatar inconnu');
 const objects=r.scenarios[r.active_index]?.objects||[];
 const obj=objects.find(o=>o.uid===target);
 if(target!==null && !obj)throw new Error('Poste introuvable');
 if(obj && Math.hypot(obj.x-p.avatar.x,obj.y-p.avatar.y)>140)throw new Error('Rapproche-toi du poste');
 const allowed={préparer:['table','evier','eplucheuse','frigo'],cuisiner:['cuisson','marmite','sauteuse','four','friteuse'],
   porter:['chariot','table','frigo','meuble_chaud'],pousser:['chariot'],plonge:['plonge','evier'],
   servir:['table','meuble_chaud','chariot'],nettoyer:['plonge','evier','table']};
 if(allowed[action] && (!obj || !allowed[action].includes(obj.type)))throw new Error('Choisis un poste adapté à cette action');
 const next={...p.avatar,action,target:obj?.uid??null};
 await sql`UPDATE room_participants SET avatar=${JSON.stringify(next)}::jsonb,last_seen_at=now() WHERE room_id=${room} AND id=${id}`;
 return event(room,id,'interaction',{id,action,target:obj?.uid??null,by:id});
}
export async function adjustRoom(room,actor,role,command,data){
 const sql=db();const host=role==='host';
 if(command==='pause' || command==='lock'){
  if(!host)throw new Error('Action réservée à l’animateur');
  const v=!!data.value;
  const rows=command==='pause'?await sql`UPDATE rooms SET paused=${v},updated_at=now() WHERE id=${room} RETURNING revision`:
  await sql`UPDATE rooms SET locked=${v},updated_at=now() WHERE id=${room} RETURNING revision`;
  if(!rows.length)throw new Error('Salle introuvable');
  return event(room,actor,command,{value:v});
 }
 if(command==='layout'){
  const [r]=await sql`SELECT revision,locked FROM rooms WHERE id=${room}`;
  if(!r)throw new Error('Salle introuvable');
  if(r.locked&&!host)throw new Error('Aménagement verrouillé par l’animateur');
  const expected=Number(data.revision);
  if(!Number.isSafeInteger(expected))throw new Error('Version manquante');
  const scenarios=sanitizeScenarios(data.scenarios);
  const active=Number(data.active_index);
  if(!Number.isSafeInteger(active)||active<0||active>=scenarios.length)throw new Error('Scénario actif invalide');
  const upd=await sql`UPDATE rooms SET scenarios=${JSON.stringify(scenarios)}::jsonb,active_index=${active},revision=revision+1,updated_at=now()
   WHERE id=${room} AND revision=${expected} AND (NOT locked OR ${host}) RETURNING revision`;
  if(!upd.length)throw new Error('Conflit de modification : actualise la salle');
  return event(room,actor,'layout',{scenarios,active_index:active,revision:Number(upd[0].revision),by:actor});
 }
 throw new Error('Commande inconnue');
}
