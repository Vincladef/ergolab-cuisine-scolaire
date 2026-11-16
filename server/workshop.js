import {randomUUID} from 'node:crypto';
import {db} from './db.js';
import {event} from './model.js';
import {analyzeEvents,sanitizeScript,sanitizeCriteria,summarizeRuns} from './analysis.js';
const CAT=new Set(['manutention','posture','accident','coordination','flux','obstacle','circulation','autre']);
const finite = value=>Number.isFinite(Number(value));
function publicly(run){return {...run,scenario_index:Number(run.scenario_index)};}
export async function getWorkshop(room){
 const sql=db();
 const [w]=await sql`SELECT script,design_criteria,recommendations FROM room_workshops WHERE room_id=${room}`;
 const runs=await sql`SELECT id,scenario_index,title,started_at,ended_at,status FROM room_runs WHERE room_id=${room} ORDER BY started_at DESC LIMIT 60`;
 const obs=await sql`SELECT id,run_id,actor_id,scenario_index,category,severity,comment,location,created_at FROM room_observations WHERE room_id=${room} ORDER BY created_at DESC LIMIT 500`;
 const evt=await sql`SELECT seq,kind,payload,created_at FROM room_events WHERE room_id=${room} ORDER BY seq DESC LIMIT 6000`;
 const events=evt.reverse();
 return {script:w?.script||[],criteria:w?.design_criteria||[],recommendations:w?.recommendations||[],runs:summarizeRuns(runs.map(publicly),events,obs),observations:obs,
  activeRun:runs.find(r=>r.status==='active')?.id||null,
  timeline:events.filter(e=>e.kind!=='move').slice(-400),recentPositions:events.filter(e=>e.kind==='move').slice(-350),
  metrics:analyzeEvents(events)};
}
export async function saveScript(room,actor,role,data){
 if(role!=='host')throw new Error('Modification réservée à l’animateur');
 const script=sanitizeScript(data.script),criteria=sanitizeCriteria(data.criteria||[]),recommendations=sanitizeCriteria(data.recommendations||[]);
 const sql=db();
 await sql`INSERT INTO room_workshops(room_id,script,design_criteria,recommendations) VALUES (${room},${JSON.stringify(script)}::jsonb,${JSON.stringify(criteria)}::jsonb,${JSON.stringify(recommendations)}::jsonb)
 ON CONFLICT(room_id) DO UPDATE SET script=excluded.script,design_criteria=excluded.design_criteria,recommendations=excluded.recommendations,updated_at=now()`;
 await event(room,actor,'workshop',{updated:true,by:actor});
 return {script,criteria,recommendations};
}
export async function startRun(room,actor,role,data){
 if(role!=='host')throw new Error('Action réservée à l’animateur');
 const sql=db();
 const [r]=await sql`SELECT active_index,scenarios FROM rooms WHERE id=${room}`;
 const scenario=Number.isInteger(data.scenario_index)?data.scenario_index:r.active_index;
 if(scenario<0||scenario>=r.scenarios.length)throw new Error('Scénario inconnu');
 const title=String(data.title||`Simulation ${r.scenarios[scenario].name}`).slice(0,120);
 const id=randomUUID();
 await sql`INSERT INTO room_runs(id,room_id,scenario_index,title,started_by) VALUES (${id},${room},${scenario},${title},${actor})`;
 await event(room,actor,'run_start',{id,scenario_index:scenario,title});
 return {id,scenario_index:scenario,title};
}
export async function endRun(room,actor,role){
 if(role!=='host')throw new Error('Action réservée à l’animateur');
 const sql=db();const [r]=await sql`UPDATE room_runs SET status='completed',ended_at=now() WHERE room_id=${room} AND status='active' RETURNING id`;
 if(!r)throw new Error('Aucune simulation active');
 await event(room,actor,'run_end',{id:r.id});return {id:r.id};
}
export async function addObservation(room,actor,data){
 const category=CAT.has(data.category)?data.category:'autre',comment=String(data.comment||'').trim().slice(0,1200);
 if(comment.length<3)throw new Error('Décris la situation observée');
 const severity=Number(data.severity);if(![1,2,3].includes(severity))throw new Error('Gravité invalide');
 const x=data.x,y=data.y;
 const location=finite(x)&&finite(y)&&+x>=0&&+x<=1571&&+y>=0&&+y<=1088?{x:+x,y:+y}:null;
 const sql=db();
 const [r]=await sql`SELECT active_index FROM rooms WHERE id=${room}`;
 const [run]=await sql`SELECT id FROM room_runs WHERE room_id=${room} AND status='active' LIMIT 1`;
 const [obs]=await sql`INSERT INTO room_observations(room_id,run_id,actor_id,scenario_index,category,severity,comment,location)
 VALUES (${room},${run?.id||null},${actor},${r.active_index},${category},${severity},${comment},${JSON.stringify(location)}::jsonb)
 RETURNING id,run_id,actor_id,scenario_index,category,severity,comment,location,created_at`;
 await event(room,actor,'observation',{id:Number(obs.id),category,severity,by:actor,comment});
 return obs;
}
export async function triggerStep(room,actor,role,data){
 if(role!=='host')throw new Error('Seul l’animateur déclenche les événements');
 const sql=db();const [run]=await sql`SELECT id FROM room_runs WHERE room_id=${room} AND status='active'`;
 if(!run)throw new Error('Démarre une simulation');
 const [w]=await sql`SELECT script FROM room_workshops WHERE room_id=${room}`;
 const step=(w?.script||[]).find(e=>e.id===String(data.step_id||''));
 if(!step)throw new Error('Étape inconnue');
 const result=await event(room,actor,'script_step',{run_id:run.id,step,by:actor});return result;
}
