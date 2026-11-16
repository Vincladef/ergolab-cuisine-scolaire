import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import {authenticate,snapshot} from '../server/model.js';
import {getWorkshop} from '../server/workshop.js';
const A4=[595.28,841.89], INK=rgb(.13,.24,.25),GREEN=rgb(.19,.39,.35),ACCENT=rgb(.72,.41,.27),MUTED=rgb(.43,.51,.49);
const clean=v=>String(v??'').replace(/[\u2013\u2014]/g,'-').replace(/[\u2018\u2019]/g,"'").replace(/[\u201c\u201d]/g,'"').replace(/[^\x20-\x7E\u00A0-\u00FF\n]/g,' ').replace(/\s+/g,' ').trim();
function chunks(text,font,size,width){const words=clean(text).split(' ');const lines=[],part=[];for(const word of words){const candidate=[...part,word].join(' ');if(font.widthOfTextAtSize(candidate,size)>width&&part.length){lines.push(part.join(' '));part.splice(0,part.length,word);}else part.push(word);}if(part.length)lines.push(part.join(' '));return lines;}
export async function buildReport({room,snapshot:roomState,workshop,screens=[]}){
 const pdf=await PDFDocument.create();const normal=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold);let page,y,number=0;
 const newPage=()=>{page=pdf.addPage(A4);number++;y=785;page.drawRectangle({x:0,y:800,width:A4[0],height:42,color:GREEN});page.drawText('ERGOLAB   /   COMPTE RENDU DE SIMULATION',{x:36,y:814,font:bold,size:10,color:rgb(1,1,1)});page.drawLine({start:{x:36,y:45},end:{x:559,y:45},thickness:.5,color:rgb(.82,.86,.84)});page.drawText(`Atelier cuisine scolaire  |  Salle ${room}  |  Page ${number}`,{x:36,y:31,font:normal,size:9,color:MUTED});};
 const ensure=(n=35)=>{if(y-n<65)newPage()};
 const header=(text)=>{ensure(65);y-=15;page.drawText(clean(text),{x:36,y,font:bold,size:17,color:INK});y-=28;};
 const para=(text,size=10,indent=0)=>{for(const ln of chunks(text,normal,size,520-indent)){ensure(17);page.drawText(ln,{x:36+indent,y,font:normal,size,color:INK});y-=size+6;}y-=3;};
 const bullet=(text)=>{ensure(15);page.drawCircle({x:43,y:y+3,size:2,color:ACCENT});para(text,10,17);};
 const small=(text)=>{ensure(15);page.drawText(clean(text).slice(0,110),{x:36,y,font:normal,size:9,color:MUTED});y-=17;};
 newPage();y=765;page.drawText('SIMULATION ERGONOMIQUE',{x:36,y,font:bold,size:11,color:ACCENT});y-=39;
 page.drawText('Cuisine scolaire :',{x:36,y,font:bold,size:29,color:INK});y-=36;
 page.drawText('analyse collective des scénarios',{x:36,y,font:bold,size:23,color:INK});y-=28;
 para('Dossier de reference : Atelier distanciel, simulation du travail. Maquette basee sur le plan p.5 et la bibliotheque d equipements p.6.');
 small('Document genere le '+new Date().toLocaleString('fr-FR'));
 para(`Salle ${room}  |  ${roomState?.participants?.length||0} participants  |  ${roomState?.scenarios?.length||0} amenagements`);
 header('1. Repères pour la conception');for(const line of workshop.criteria||[])bullet(line);if(!(workshop.criteria||[]).length)para('Aucun repere saisi pendant cet atelier.');
 header('2. Script d événements');for(const step of workshop.script||[]){small(`${Math.round(step.at/60)} min  |  ${step.title}`);if(step.description)para(step.description,9,11);}if(!(workshop.script||[]).length)para('Script non renseigne.');
 header('3. Scénarios d aménagement');for(const [i,scenario] of (roomState.scenarios||[]).entries()){bullet(`${i+1}. ${scenario.name} - ${scenario.objects?.length||0} equipements`);if(scenario.notes)para(scenario.notes,9,13);}
 for(const screen of screens.slice(0,12)){
  if(typeof screen?.data!=='string'||!/^data:image\/jpeg;base64,/.test(screen.data)||screen.data.length>700000)continue;
  try{const raw=Buffer.from(screen.data.split(',')[1],'base64');const img=await pdf.embedJpg(raw);ensure(330);
   small('Visuel de la maquette : '+(screen.name||'Aménagement'));
   const maxW=514,maxH=305, scale=Math.min(maxW/img.width,maxH/img.height);
   page.drawImage(img,{x:40,y:y-img.height*scale,width:img.width*scale,height:img.height*scale});y-=img.height*scale+20;
  }catch{/* image non exploitable : conserver le reste du rapport */}
 }
 header('4. Résultats des simulations');
 const runs=workshop.runs||[];
 for(const r of runs){ensure(65);page.drawText(clean(r.title).slice(0,72),{x:36,y,font:bold,size:12,color:GREEN});y-=20;
  small(`Scenario ${r.scenario_index+1}  |  ${r.status==='completed'?'Termine':'En cours'}  |  ${new Date(r.started_at).toLocaleString('fr-FR')}`);
  const m=r.stats||{};para(`Distance mesuree ${m.distance_m||0} m ; attente declaree ${m.wait_s||0} s ; proximites estimees ${m.crossings_estimated||0} ; actions ${m.interactions||0}.`,10,8);
 }if(!runs.length)para('Aucune simulation enregistree.');
 header('5. Observations recueillies');for(const o of (workshop.observations||[]).slice(0,100)){small(`${o.category}  |  criticite ${o.severity}/3  |  ${new Date(o.created_at).toLocaleString('fr-FR')}`);para(o.comment,10,10);}if(!(workshop.observations||[]).length)para('Aucune observation saisie.');
 header('6. Exigences pour le cahier des charges');for(const r of workshop.recommendations||[])bullet(r);if(!(workshop.recommendations||[]).length)para('Aucune exigence finale renseignee.');
 header('7. Limites de la méthode');para('Les mesures sont exploratoires et refletent les actions enregistrees. Les distances proviennent d une calibration approximative de 42,82 px par metre sur un rendu PDF. Une proximite temporelle de deux agents n etablit pas une collision ni un risque de TMS. Les attentes sont declarees par les utilisateurs. Les murs, ouvertures et acces doivent etre controles sur le plan cote original. La validation repose sur les commentaires des agents et la confrontation des scenarios.');
 return await pdf.save();
}
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');if(req.method!=='POST')return res.status(405).json({error:'Méthode interdite'});
 try{if(Number(req.headers['content-length']||0)>4_000_000)return res.status(413).json({error:'Rapport trop volumineux'});
 const d=typeof req.body==='string'?JSON.parse(req.body):req.body||{};
 const identity=await authenticate(d.room,d.id,d.token);if(!identity)return res.status(401).json({error:'Session non autorisée'});
 const [roomState,workshop]=await Promise.all([snapshot(d.room),getWorkshop(d.room)]);
 const buf=await buildReport({room:d.room,snapshot:roomState,workshop,screens:Array.isArray(d.screens)?d.screens:[]});
 res.setHeader('Content-Type','application/pdf');res.setHeader('Content-Disposition',`attachment; filename="ergolab-${d.room}.pdf"`);res.setHeader('Content-Length',buf.length);
 return res.status(200).end(Buffer.from(buf));
 }catch(e){return res.status(400).json({error:String(e.message||'Export indisponible')});}
}
