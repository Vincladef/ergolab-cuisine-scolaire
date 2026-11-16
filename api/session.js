import { createRoom,joinRoom,authenticate,snapshot } from '../server/model.js';
const MAX_BYTES=4096;
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 res.setHeader('Content-Type','application/json; charset=utf-8');
 if(req.method==='GET') return res.status(200).json({name:'ErgoLab',status:process.env.DATABASE_URL?'ready':'database_not_configured'});
 if(req.method!=='POST')return res.status(405).json({error:'Méthode interdite'});
 try {
  const len=Number(req.headers['content-length']||0);if(len>MAX_BYTES)throw new Error('Requête trop volumineuse');
  const data=typeof req.body==='string'?JSON.parse(req.body):req.body||{};
  if(!data || typeof data!=='object')throw new Error('Requête invalide');
  let result;
  switch(data.action){
   case 'create': result=await createRoom(data.nickname,data.color);break;
   case 'join':result=await joinRoom(data.room,data.nickname,data.color);break;
   case 'resume':{
    const p=await authenticate(data.room,data.id,data.token);
    if(!p)return res.status(401).json({error:'Identité expirée ou invalide'});
    result={room:p.room,id:p.id,token:data.token,role:p.role,snapshot:await snapshot(p.room)};break;
   }
   default:throw new Error('Action inconnue');
  }
  return res.status(200).json(result);
 } catch(err) {return res.status(400).json({error:err.message||'Erreur de session'});}
}
