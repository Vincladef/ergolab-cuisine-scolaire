import {authenticate} from '../server/model.js';
import {getWorkshop,saveScript,startRun,endRun,addObservation,triggerStep} from '../server/workshop.js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='POST')return res.status(405).json({error:'Méthode non autorisée'});
 try {
  if(Number(req.headers['content-length']||0)>200000)return res.status(413).json({error:'Message trop long'});
  const data=typeof req.body==='string'?JSON.parse(req.body):req.body||{};
  const user=await authenticate(data.room,data.id,data.token);
  if(!user)return res.status(401).json({error:'Session non autorisée'});
  let result;
  switch(data.action){
   case 'get':result=await getWorkshop(data.room);break;
   case 'save_script':result=await saveScript(data.room,user.id,user.role,data);break;
   case 'start_run':result=await startRun(data.room,user.id,user.role,data);break;
   case 'end_run':result=await endRun(data.room,user.id,user.role);break;
   case 'observation':result=await addObservation(data.room,user.id,data);break;
   case 'trigger':result=await triggerStep(data.room,user.id,user.role,data);break;
   default:return res.status(400).json({error:'Commande inconnue'});
  }
  return res.status(200).json(result);
 }catch(e){return res.status(400).json({error:String(e.message||'Erreur atelier')});}
}
