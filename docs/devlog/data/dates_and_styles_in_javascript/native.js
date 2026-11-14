// The patterns of rxbench.nim on JavaScript's own RegExp: node native.js
let s=''; for(let i=0;i<4000;i++) s+=`key${i} : some value number ${i}\n`;
function t(l,f){const t0=performance.now();for(let r=0;r<3;r++)f();console.log(l.padEnd(46),((performance.now()-t0)/3).toFixed(2),'ms')}
t('native: g walk, 2 groups',()=>[...s.matchAll(/(\w+)[ \t]*:[ \t]*([^\n]*)/g)]);
t('native: sticky lexer',()=>{const w=/\w+/y,c=/[ \t]*:[ \t]*/y;let at=0;while(at<s.length){w.lastIndex=at;if(w.test(s)&&w.lastIndex>at){at=w.lastIndex;continue}c.lastIndex=at;if(c.test(s)&&c.lastIndex>at){at=c.lastIndex;continue}at++}});
