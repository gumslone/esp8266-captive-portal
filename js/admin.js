function id(i){return document.getElementById(i);}
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function req(u,cb){var x=new XMLHttpRequest();x.onreadystatechange=function(){if(this.readyState==4){cb(this.status,this.responseText);}};x.open('GET',u,true);x.send();}
function exec(cmd,cb){req('/x?action=execute&execute_command='+encodeURIComponent(cmd)+'&rnd='+Math.random(),function(st,t){id('msg').innerHTML='<pre>'+esc(t)+'</pre>';if(cb)cb(t);});}
function execq(cmd,cb){req('/x?action=execute&execute_command='+encodeURIComponent(cmd)+'&rnd='+Math.random(),function(st,t){cb(t);});}
function runf(n){if(confirm('Execute '+n+'?'))exec("=pcall(function() dofile('"+n+"') end)");}
function compf(n){exec("=node.compile('"+n+"')",flist);}
function viewFails(){id('lf').textContent='Loading...';
  execq("local f=file.open('login_fail.txt','r') if f then print(f:read(2200) or '') f:close() else print('(no failed logins)') end",
    function(t){id('lf').textContent=(t||'').trim()||'(no failed logins)';});}
function clearFails(){if(confirm('Clear the failed-login log?'))execq("file.remove('login_fail.txt')",viewFails);}
// common commands: kept here (streamed) rather than in admin.html (rendered in RAM)
var CMDS=[['Common commands...',''],
  ['Free heap (bytes)','=node.heap()'],
  ['Lua memory in use (KB)','=collectgarbage("count")'],
  ['Uptime (s)','=tmr.time()'],
  ['Flash: free, used, total','=file.fsinfo()'],
  ['Firmware / chip info','=node.info()'],
  ['Chip ID','=node.chipid()'],
  ['AP IP, mask, gateway','=wifi.ap.getip()'],
  ['Connected clients (MAC, IP)','for m,i in pairs(wifi.ap.getclient()) do print(m,i) end'],
  ['Free memory now','collectgarbage() print(node.heap())'],
  ['Compile all modules','dofile("compile_all.lua")'],
  ['Clear saved settings (then restart)','file.remove("portal_config.lua")']];
function fillCmds(){var s=id('cs');for(var i=0;i<CMDS.length;i++){var o=document.createElement('option');o.text=CMDS[i][0];o.value=CMDS[i][1];s.add(o);}}
fillCmds();
var AUTH=['open','WEP','WPA','WPA2','WPA/WPA2'];
function scan(){id('sc').innerHTML='Scanning...';
  req('/x?action=scan&rnd='+Math.random(),function(st,t){
    if(st!=200){id('sc').innerHTML='Scan failed ('+st+') - sign in again.';return;}
    var r=(t||'').split('\n'),nets=[],ours='';
    for(var i=0;i<r.length;i++){var p=r[i].split('\t');if(p[0]=='#'){ours=p[1];continue;}
      if(p.length>=5)nets.push({s:p[0],r:+p[1],c:p[2],a:AUTH[+p[3]]||p[3]});}
    nets.sort(function(a,b){return b.r-a.r;});
    var h='<table><tr><th>SSID</th><th>Signal</th><th>Ch</th><th>Security</th></tr>';
    for(var j=0;j<nets.length;j++){var n=nets[j];
      h+='<tr><td>'+(n.s?esc(n.s):'<i>(hidden)</i>')+'</td><td>'+n.r+' dBm</td><td>'+(n.c==ours?'<b>'+esc(n.c)+'</b>':esc(n.c))+'</td><td>'+esc(n.a)+'</td></tr>';}
    id('sc').innerHTML=h+'</table><p>'+nets.length+' network(s)'+(ours?'; this portal is on channel <b>'+esc(ours)+'</b>':'')+'</p>';});}
function runCmd(){var c=id('cmd').value.trim();if(c)exec(c);}
function restart(){if(confirm('Restart the device?')){id('msg').innerHTML='Restarting...';
  execq('tmr.create():alarm(500,tmr.ALARM_SINGLE,node.restart)',function(){id('msg').innerHTML='Restarting... reload this page in a few seconds.';});}}
function lq(s){return "'"+s.replace(/\\/g,'\\\\').replace(/'/g,"\\'")+"'";}
function renf(n){var t=prompt('Rename '+n+' to:',n);if(t&&t!=n)exec('=file.rename('+lq(n)+','+lq(t)+')',flist);}
function delf(n){if(confirm('Delete '+n+'? This cannot be undone.'))exec("file.remove('"+n+"')",flist);}
function lnk(f,n,l){return '<a href="javascript:;" onclick="'+f+'(\''+n+'\')">'+l+'</a>';}
function flist(){req('/x?action=execute&execute_command='+encodeURIComponent("for k,v in pairs(file.list()) do print(k..\"\t\"..v) end print(\"#\t\"..file.fsinfo())")+'&rnd='+Math.random(),function(st,t){
  if(st!=200){id('fl').innerHTML='File list failed ('+st+') - sign in again.';return;}
  var r=(t||'').split('\n'),h='<table><tr><th>File</th><th>Size</th><th></th></tr>',n=0,free='';
  for(var i=0;i<r.length;i++){var p=r[i].split('\t');if(p.length<2)continue;
    var fn=p[0].replace(/\r/,'').trim(),sz=p[1].replace(/\r/,'').trim();if(!fn)continue;
    if(fn=='#'){free=sz;continue;}n++;var a=[];
    if(!/\.(lc|mp3|png|ico|gz)$/.test(fn))a.push(lnk('editf',fn,'edit'));
    if(/\.lua$/.test(fn))a.push(lnk('compf',fn,'compile'));
    if(/\.(lua|lc)$/.test(fn))a.push(lnk('runf',fn,'execute'));
    a.push(lnk('renf',fn,'rename'));a.push(lnk('delf',fn,'delete'));
    h+='<tr><td><a href="/'+fn+'" target="_blank">'+esc(fn)+'</a></td><td>'+esc(sz)+'</td><td>'+a.join(' | ')+'</td></tr>';}
  h+='</table><p>'+n+' file(s)'+(free?', '+esc(free)+' bytes free':'')+'</p>';id('fl').innerHTML=h;
  var names=r.map(function(l){return l.split('\t')[0].trim();});
  // portal_x.html.gz (pre-gzipped page) is listed as portal_x.html
  var pages=names.map(function(f){return f.replace(/\.gz$/,'');}).filter(function(f,i,a){return /^portal_.*\.html$/.test(f)&&a.indexOf(f)==i;});
  fillSel('pg',pages);
  fillSel('lg',names.filter(function(f){return /^login.*\.html$/.test(f);}));});}
// captive page / login form pickers: options come from the file list (no extra request)
function fillSel(sid,names){var s=id(sid),act=s.getAttribute('data-active'),cur=s.value||act;s.innerHTML='';
  names.sort();for(var i=0;i<names.length;i++){var o=document.createElement('option');o.value=names[i];
    o.text=names[i]+(names[i]==act?'  (active)':'');if(names[i]==cur)o.selected=true;s.add(o);}}
var KIND={page:['pg','pgm','Active page: '],login:['lg','lgm','Active login form: ']};
function setPage(kind){var k=KIND[kind],n=id(k[0]).value;if(!n)return;
  req('/x?action=set_page&kind='+kind+'&name='+encodeURIComponent(n)+'&rnd='+Math.random(),function(st){
    if(st==200){id(k[0]).setAttribute('data-active',n);id(k[1]).innerHTML=k[2]+esc(n);flist();}
    else id(k[1]).innerHTML='Could not activate ('+st+')';});}
function ename(){return encodeURIComponent(id('en').value.trim());}
var _ld=null; // name of the file currently loaded in the editor
function loadPage(){id('pm').innerHTML='';var n=id('en').value.trim();req('/'+ename()+'?rnd='+Math.random(),function(st,t){
  if(st==200){id('h').value=t;_ld=n;id('pm').innerHTML='Loaded '+esc(n);}else id('pm').innerHTML='Load failed ('+st+')';});}
function editf(n){id('en').value=n;loadPage();id('h').scrollIntoView();}
var _l,_c,_t;
function savePage(){if(!ename()){alert('Enter a file name');return;}
  var n=id('en').value.trim();if(n!==_ld&&!confirm(n+' was not loaded into the editor. Overwrite it with the text above?'))return;
  _l=id('h').value.split('\n');if(_l.length>1&&_l[_l.length-1]==='')_l.pop(); // no extra newline per save
  _t=_l.length;if(_t>200&&!confirm(_t+' lines: saving sends one request per line and may be slow or fail. Continue?'))return;
  _c=0;id('pm').innerHTML='Saving...';sendLine();}
function sendLine(){var first=(_c===0)?'&first=1':'';
  req('/x?action=page_append&name='+ename()+first+'&line='+encodeURIComponent(_l[_c])+'&rnd='+Math.random(),function(st){
    if(st!=200){id('pm').innerHTML='Save failed ('+st+') - sign in again.';return;}
    _c++;if(_c<_t){id('pm').innerHTML='Line '+_c+'/'+_t;sendLine();}else{id('pm').innerHTML='Saved ('+_t+' lines).';}});}
function uploadFile(){var f=id('f').files[0],n=id('fn').value.trim();if(!f||!n){alert('Choose a file and a name');return;}
  id('um').innerHTML='Uploading...';var x=new XMLHttpRequest();
  x.onreadystatechange=function(){if(this.readyState==4){id('um').innerHTML=(this.status==200?'Uploaded '+esc(n):'Upload failed ('+this.status+')');flist();}};
  x.open('POST','/admin/upload?name='+encodeURIComponent(n),true);x.send(f);}
// editor loads on demand (Load / edit); file list waits for the page's own
// requests to finish, so the ESP never juggles several connections at once
// admin.html is static (served gzipped); the current settings come from one
// small request: "key=urlencoded value" lines. Then the file list.
function loadSettings(){req('/x?action=settings&rnd='+Math.random(),function(st,t){
  if(st!=200){id('sm').innerHTML='Could not load settings ('+st+') - sign in again.';return;}
  var v={},r=(t||'').split('\n');
  for(var i=0;i<r.length;i++){var j=r[i].indexOf('=');if(j>0)v[r[i].slice(0,j)]=decodeURIComponent(r[i].slice(j+1));}
  document.title='Admin - '+(v.ssid||'');id('s').value=v.ssid||'';id('w').value=v.wpa||'';
  id('u').value=v.user||'';id('p').value=v.pass||'';id('rl').checked=v.rl=='1';
  id('pg').setAttribute('data-active',v.page||'');id('lg').setAttribute('data-active',v.login||'');
  if(!id('en').value)id('en').value=v.page||'';
  flist();});}
window.onload=loadSettings;
