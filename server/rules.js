export const WIDTH = 1571, HEIGHT = 1088;
export const EQUIPMENT = new Set(['chariot','evier','lave_mains','plonge','etagere','table','frigo','sauteuse','cuisson','marmite','friteuse','four','meuble_chaud','eplucheuse']);
export const ACTIONS = new Set(['libre','préparer','cuisiner','porter','pousser','plonge','servir','attendre','nettoyer','livrer']);
export const COLORS = new Set(['#CE6D3C','#3C82B5','#639F76','#9B72BA','#C59D40','#D06E89','#3B968D','#8A7B63']);
const FINITE = v => typeof v === 'number' && Number.isFinite(v);
export function validatePosition(x,y) { return FINITE(x) && FINITE(y) && x>=20 && x<=WIDTH-20 && y>=80 && y<=HEIGHT-22; }
export function cleanNickname(str) { return typeof str === 'string' ? str.trim().replace(/[<>\n\r]/g,'').slice(0,32) || 'Participant' : 'Participant'; }
export function cleanColor(str) { return COLORS.has(str) ? str : '#3C82B5'; }
export function cleanAction(action) {return ACTIONS.has(action) ? action : 'libre';}
export function sanitizeScenarios(input) {
  if (!Array.isArray(input) || !input.length || input.length>12) throw new Error('Nombre de scénarios non autorisé');
  return input.map(sc => {
    if (!sc || typeof sc !== 'object' || !Array.isArray(sc.objects) || sc.objects.length>150) throw new Error('Scénario invalide');
    const uids = new Set();
    const objects = sc.objects.map(o => {
      if (!o || !EQUIPMENT.has(o.type) || !Number.isSafeInteger(o.uid) || o.uid<1 || o.uid>1e9 || uids.has(o.uid)) throw new Error('Équipement invalide');
      if (!validatePosition(o.x,o.y) || !FINITE(o.rot)) throw new Error('Position hors du plan');
      uids.add(o.uid);
      return {uid:o.uid,type:o.type,x:o.x,y:o.y,rot:((o.rot%360)+360)%360};
    });
    return { name:String(sc.name||'Aménagement').slice(0,70),notes:String(sc.notes||'').slice(0,3000),objects };
  });
}
export function obstacleAt(x,y,objects,ignoreUid=0) {
  const dims = {
    chariot:[29,17],evier:[31,85],lave_mains:[22,46],plonge:[31,181],etagere:[34,106],table:[28,83],frigo:[35,85],sauteuse:[41,43],cuisson:[41,27],marmite:[41,34],friteuse:[41,37],four:[43,53],meuble_chaud:[32,74],eplucheuse:[35,37]
  };
  for (const o of objects) {
    if(o.uid===ignoreUid || !dims[o.type]) continue;
    const [w,h] = dims[o.type]; const angle = -(o.rot||0)*Math.PI/180;
    const dx=x-o.x,dy=y-o.y,rx=dx*Math.cos(angle)-dy*Math.sin(angle),ry=dx*Math.sin(angle)+dy*Math.cos(angle);
    if(Math.abs(rx)<w/2+11 && Math.abs(ry)<h/2+11) return true;
  }
  return false;
}
export function canMoveAvatar(x,y,scenarios,index) {
  if (!validatePosition(x,y)) return false;
  const sc = scenarios[index];
  return !obstacleAt(x,y,sc?.objects||[]);
}
