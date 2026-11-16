import { createServer } from 'node:http';
import { WebSocketServer,WebSocket } from 'ws';
import { authenticate,snapshot,latestEventSeq,eventsSince,move,interaction,adjustRoom,event,heartbeat,markDisconnected } from '../server/model.js';
// Vercel Functions websocket entrypoint. Each instance may host only some room peers.
// The Neon event log bridges separate instances; packets are deduplicated by seq client-side.
const server=createServer((req,res)=>{res.writeHead(200,{'content-type':'text/plain'});res.end('ErgoLab websocket endpoint');});
const wss=new WebSocketServer({server,maxPayload:8192,perMessageDeflate:false});
const peers=new Set();
const lastByRoom=new Map();
const send=(ws,packet)=>{if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify(packet));};
const localBroadcast=(room,packet)=>{for(const peer of peers)if(peer.room===room)send(peer.ws,packet);};
let pollBusy=false;
async function pollUpdates(){
 if(pollBusy||!peers.size)return;
 pollBusy=true;
 try {
  for(const room of new Set([...peers].map(p=>p.room).filter(Boolean))){
    const last=lastByRoom.get(room)||0;
    const events=await eventsSince(room,last);
    for(const packet of events){lastByRoom.set(room,Math.max(lastByRoom.get(room)||0,packet.seq));localBroadcast(room,packet);}
  }
 } catch(e){console.error('event polling failed:',e.message);} finally{pollBusy=false;}
}
const ticker=setInterval(pollUpdates,700);ticker.unref?.();
wss.on('connection',ws=>{
 const peer={ws,room:null,id:null,role:null,joined:false,lastMove:0};peers.add(peer);
 const timeout=setTimeout(()=>{if(!peer.joined)ws.close(1008,'Identification manquante');},15000);
 ws.on('message', async raw=>{
  if(raw.length>8192)return ws.close(1009,'Message trop long');
  let data;try{data=JSON.parse(raw.toString('utf8'));}catch{return send(ws,{kind:'error',message:'JSON invalide'});}
  try {
   if(!peer.joined){
    if(data.op!=='hello')throw new Error('Identification obligatoire');
    const identity=await authenticate(data.room,data.id,data.token);
    if(!identity)throw new Error('Identité inconnue');
    peer.room=identity.room;peer.id=identity.id;peer.role=identity.role;peer.joined=true;clearTimeout(timeout);
    const [state,cursor]=await Promise.all([snapshot(peer.room),latestEventSeq(peer.room)]);
    if(!lastByRoom.has(peer.room))lastByRoom.set(peer.room,cursor);
    send(ws,{kind:'welcome',state,cursor,me:peer.id});
    const myself=state.participants.find(p=>p.id===peer.id);
    if(myself){
      const joined=await event(peer.room,peer.id,'presence',{participant:{...myself,connected:true}});
      lastByRoom.set(peer.room,Math.max(lastByRoom.get(peer.room)||0,joined.seq));
      localBroadcast(peer.room,joined);
    }
    return;
   }
   if(data.op==='ping'){
     await heartbeat(peer.room,peer.id);
     send(ws,{kind:'pong',t:Date.now()});return;
   }
   if(data.op==='refresh'){
     send(ws,{kind:'snapshot',state:await snapshot(peer.room),cursor:await latestEventSeq(peer.room)});return;
   }
   let result=null;
   switch(data.op){
    case 'move':
      if(Date.now()-peer.lastMove<90)return;
      peer.lastMove=Date.now();result=await move(peer.room,peer.id,data);break;
    case 'interact':result=await interaction(peer.room,peer.id,data);break;
    case 'layout':result=await adjustRoom(peer.room,peer.id,peer.role,'layout',data);break;
    case 'pause':case 'lock':result=await adjustRoom(peer.room,peer.id,peer.role,data.op,data);break;
    default:throw new Error('Commande inconnue');
   }
   if(result){lastByRoom.set(peer.room,Math.max(lastByRoom.get(peer.room)||0,result.seq));localBroadcast(peer.room,result);}
  } catch(error){send(ws,{kind:'error',message:String(error.message||'Erreur')});}
 });
 ws.on('close',()=>{
   clearTimeout(timeout);peers.delete(peer);
   if(peer.room){
     if(!([...peers].some(p=>p.room===peer.room)))lastByRoom.delete(peer.room);
     void (async()=>{
       try {
         if(!([...peers].some(p=>p.room===peer.room && p.id===peer.id))){
           await markDisconnected(peer.room,peer.id);
           const packet=await event(peer.room,peer.id,'presence',{id:peer.id,connected:false});
           localBroadcast(peer.room,packet);
         }
       }catch(e){console.error('close update failed',e.message);}
     })();
   }
 });
 ws.on('error',()=>{peers.delete(peer);});
});
export default server;
