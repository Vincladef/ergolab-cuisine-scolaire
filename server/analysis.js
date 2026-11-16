// Metriques descriptives de traces 2D (et non diagnostic de TMS).
export const PX_PER_M = 42.82; // PDF p.5, calibration approximative.
export const round = (x,n=1) => Math.round(x*10**n)/10**n;
const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
const secondsBetween=(a,b)=>Math.max(0,(new Date(b).getTime()-new Date(a).getTime())/1000);
export function analyzeEvents(events,{until=new Date().toISOString()}={}){
  const sorted=[...events].sort((a,b)=>new Date(a.created_at)-new Date(b.created_at)||Number(a.seq)-Number(b.seq));
  const last=new Map(),waiting=new Map(),waitSeconds=new Map(),paths=new Map();
  const proximity=new Set(); const timed=new Map();
  let moved=0,interactions=0,blocked=0,stepsTriggered=0;
  for(const e of sorted){
    const p=e.payload||{};const t=e.created_at||until;
    if(e.kind==='move' && typeof p.id==='string' && Number.isFinite(+p.x) && Number.isFinite(+p.y)){
      moved++;
      const pos={x:+p.x,y:+p.y,t};
      const old=last.get(p.id);
      if(old){ const d=distance(pos,old); if(d<=120) paths.set(p.id,(paths.get(p.id)||0)+d); }
      last.set(p.id,pos);
      const bucket=Math.floor(new Date(t).getTime()/1500);
      for(const [other,op] of last){
        if(other===p.id || Math.abs(new Date(op.t)-new Date(t))>1500)continue;
        if(distance(op,pos)<50){ const key=[other,p.id].sort().join(':')+':'+bucket;proximity.add(key); }
      }
    }
    if(e.kind==='interaction'){
      interactions++; const id=p.id; if(!id)continue;
      if(waiting.has(id)){waitSeconds.set(id,(waitSeconds.get(id)||0)+secondsBetween(waiting.get(id),t));waiting.delete(id);}
      if(p.action==='attendre') waiting.set(id,t);
    }
    if(e.kind==='blocked') blocked++;
    if(e.kind==='script_step')stepsTriggered++;
    const bucket=Math.floor(new Date(t).getTime()/60000);
    timed.set(bucket,(timed.get(bucket)||0)+1);
  }
  for(const [id,started] of waiting)waitSeconds.set(id,(waitSeconds.get(id)||0)+secondsBetween(started,until));
  const byAgent=Object.fromEntries([...last.keys()].sort().map(id=>[id,{distance_m:round((paths.get(id)||0)/PX_PER_M,2),wait_s:round(waitSeconds.get(id)||0,1)}]));
  return {distance_m:round([...paths.values()].reduce((a,b)=>a+b,0)/PX_PER_M,2),wait_s:round([...waitSeconds.values()].reduce((a,b)=>a+b,0),1),
    crossings_estimated:proximity.size,move_samples:moved,interactions,blocked_events:blocked,script_steps_triggered:stepsTriggered,agents:Object.keys(byAgent).length,
    by_agent:byAgent,events_total:events.length,calibration:'42,82 px/m, approximation issue du PDF',
    method:'Proximites temporelles <50px sur 1,5s. Attentes = actions attendre declarees. Trajets = positions consecutives; pas de diagnostic TMS.'};
}
export function summarizeRuns(runs,events,observations){
 const byRun={};for(const run of runs){
   const ev=events.filter(e=>new Date(e.created_at)>=new Date(run.started_at)&&new Date(e.created_at)<=new Date(run.ended_at||Date.now()));
   const stats=analyzeEvents(ev,{until:run.ended_at||new Date().toISOString()});
   byRun[run.id]={...run,stats,observations:observations.filter(o=>o.run_id===run.id)};
 }
 return Object.values(byRun).sort((a,b)=>new Date(b.started_at)-new Date(a.started_at));
}
export function sanitizeScript(input){
 if(!Array.isArray(input)||input.length>60)throw new Error('Le script doit contenir 60 étapes au maximum');
 const unique=new Set();
 return input.map((x,i)=>{
  if(!x||typeof x!=='object')throw new Error('Étape invalide');
  const id=String(x.id||i+1).slice(0,40);
  if(unique.has(id))throw new Error('Identifiant d’étape dupliqué');unique.add(id);
  const at=Number(x.at);
  if(!Number.isFinite(at)||at<0||at>36000)throw new Error('Horaire invalide');
  const title=String(x.title||'').trim().slice(0,100);if(!title)throw new Error('Chaque étape doit avoir un titre');
  return {id,at:Math.round(at),title,description:String(x.description||'').slice(0,600),kind:String(x.kind||'normal').slice(0,25)};
 }).sort((a,b)=>a.at-b.at);
}
export function sanitizeCriteria(input){
 if(!Array.isArray(input)||input.length>40)throw new Error('Liste trop longue');
 return input.map(v=>String(v).trim().slice(0,240)).filter(Boolean);
}
