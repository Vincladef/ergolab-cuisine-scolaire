import {authenticate,move,interaction,adjustRoom} from '../server/model.js';
// HTTP de secours si le navigateur ou la plateforme ne supporte pas l'upgrade WebSocket.
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');if(req.method!=='POST')return res.status(405).json({error:'Méthode interdite'});
 try {if(Number(req.headers['content-length']||0)>80000)return res.status(413).json({error:'Trop volumineux'});
 const d=typeof req.body==='string'?JSON.parse(req.body):req.body||{};
 const p=await authenticate(d.room,d.id,d.token);if(!p)return res.status(401).json({error:'Non autorisé'});
 let result;
 switch(d.op){case 'move':result=await move(d.room,p.id,d);break;
 case 'interact':result=await interaction(d.room,p.id,d);break;
 case 'layout':case 'lock':case 'pause':result=await adjustRoom(d.room,p.id,p.role,d.op,d);break;
 default:return res.status(400).json({error:'Opération non reconnue'});}
 return res.status(200).json(result);
 }catch(e){return res.status(400).json({error:String(e.message||'Erreur')});}
}
