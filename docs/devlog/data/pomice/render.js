// Draws the diagrams of the post on Pomice with Pele, in Node: one SVG per entry of items.json.
//   node render.js <pele.global.js of Pele 1.13.0 (npm pele, dist/)> items.json
// maxWidth 360: laid out for a phone. idPrefix keeps the ids of the three drawings apart.
const vm=require('vm'),fs=require('fs');
vm.runInThisContext(fs.readFileSync(process.argv[2],'utf8'));
const items=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
for (const [name,src] of Object.entries(items)) {
  const r=pele.render(src,{responsive:true,maxWidth:360,autoDirection:true,idPrefix:name+'-'});
  fs.writeFileSync(name+'.svg', r.svg); console.log(name, r.type, Math.round(r.width), Math.round(r.height));
}
