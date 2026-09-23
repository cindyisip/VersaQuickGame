/** Real browser + Supabase JS transport + actual migration in PGlite.
 * Authentication delivery and PostgREST HTTP are simulated locally. No live credentials. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {chromium} from 'playwright';
import {PGlite} from '@electric-sql/pglite';
const root=fileURLToPath(new URL('../../',import.meta.url));
execFileSync('npm',['run','build'],{cwd:root,env:{...process.env,VITE_SUPABASE_URL:'https://test-project.supabase.co',VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_test',APPLE_TEAM_ID:''},stdio:'pipe'});
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;
create table auth.users(id uuid primary key,raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema public,auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
await db.exec(await readFile(path.join(root,'backend/migrations/202609230001_initial.sql'),'utf8'));
const host='00000000-0000-4000-8000-000000000001',guest='00000000-0000-4000-8000-000000000002';
for(const [id,name] of [[host,'Cindy'],[guest,'Mike']])await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({display_name:name})]);
let chain=Promise.resolve();
function rpc(id,name,args={}){
 const op=chain.then(async()=>{
  assert.match(name,/^[a-z_]+$/);Object.keys(args).forEach(k=>assert.match(k,/^p_[a-z_]+$/));
  await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await db.exec(id?'set role authenticated':'set role anon');
  const keys=Object.keys(args);const values=Object.values(args).map(x=>x&&typeof x==='object'&&!Array.isArray(x)?JSON.stringify(x):x);
  const result=await db.query(`select public.${name}(${keys.map((k,i)=>`"${k}" => $${i+1}`).join(',')}) result`,values);
  return result.rows[0].result;
 });chain=op.catch(()=>{});return op;
}
await rpc(host,'bootstrap');
let game=await rpc(host,'create_game',{p_place:'HUB Silicon Valley',p_court:'3',p_starts_at:new Date().toISOString(),p_target:11,p_scoring:'sideout',p_win_by:2,p_players:JSON.stringify([{nickname:'Anna'},{nickname:'Mike'},{nickname:'<img src=x onerror=alert(1)>'}]),p_request_id:'11111111-1111-4111-8111-111111111111'});
const token=(await rpc(host,'get_invite_link',{p_game_id:game.id})).token;
const server=createServer(async(req,res)=>{
 try{
  let rel=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(!path.extname(rel))rel='/index.html';
  const target=path.resolve(root,'web/dist','.'+rel);if(!target.startsWith(path.join(root,'web/dist')+path.sep))throw new Error('path');
  const data=await readFile(target);res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png'})[path.extname(target)]||'application/octet-stream');res.end(data);
 }catch{res.statusCode=404;res.end('Not found');}
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_EXECUTABLE?{executablePath:process.env.CHROMIUM_EXECUTABLE,args:JSON.parse(process.env.CHROMIUM_ARGS||'["--no-sandbox"]')}: {})});
const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1});
const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',async d=>{errors.push('Unexpected script dialog: '+d.message());await d.dismiss();});
const epoch=Math.floor(Date.now()/1000),user={id:guest,aud:'authenticated',role:'authenticated',email:'mike@example.com',email_confirmed_at:new Date().toISOString(),app_metadata:{provider:'email',providers:['email']},user_metadata:{display_name:'Mike'},created_at:new Date().toISOString()};
const jwt=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:guest,role:'authenticated',aud:'authenticated',exp:epoch+3600,iat:epoch})).toString('base64url')+'.test';
let sent=0,offline=false;
const calls=[];
await context.route('https://test-project.supabase.co/**',async route=>{
 const req=route.request(),url=new URL(req.url());const headers={'access-control-allow-origin':'*','access-control-allow-headers':'authorization,apikey,content-type,x-client-info','content-type':'application/json'};
 if(req.method()==='OPTIONS'){await route.fulfill({status:204,headers});return;}
 try{
  let data={};const body=req.postDataJSON()||{};
  if(url.pathname==='/auth/v1/otp'){sent++;assert.equal(body.email,'mike@example.com');}
  else if(url.pathname==='/auth/v1/verify'){
   if(body.token!=='123456'){await route.fulfill({status:403,headers,body:JSON.stringify({code:'otp_expired',msg:'Code is invalid or expired.'})});return;}
   data={access_token:jwt,token_type:'bearer',expires_in:3600,expires_at:epoch+3600,refresh_token:'fictional-refresh-token',user};
  }else if(url.pathname==='/auth/v1/logout'){}
  else if(url.pathname==='/auth/v1/user')data=user;
  else if(url.pathname.startsWith('/rest/v1/rpc/')){
   const name=url.pathname.split('/').pop();calls.push(name);
   if(offline&&name==='get_invitation')throw new Error('Test connection unavailable.');
   data=await rpc(req.headers().authorization==='Bearer '+jwt?guest:null,name,body);
  }else throw new Error('Unexpected endpoint '+url.pathname);
  await route.fulfill({status:200,headers,body:JSON.stringify(data)});
 }catch(e){await route.fulfill({status:400,headers,body:JSON.stringify({message:e.message})});}
});
const visible=async text=>page.getByText(text,{exact:true}).waitFor({state:'visible'});
const shot=async name=>{await mkdir(path.join(root,'test-results/browser'),{recursive:true});await page.screenshot({path:path.join(root,'test-results/browser',name+'.png'),fullPage:true});};
try{
 await page.goto(origin+'/join/#'+token);await visible('Cindy invited you.');
 await visible('Guest - Mike');await visible('Guest - <img src=x onerror=alert(1)>');assert.equal(await page.locator('.person img').count(),0);
 assert.equal(await page.getByRole('button',{name:'Create game',exact:true}).count(),0);
 await shot('01-invitation');
 await page.getByRole('button',{name:'Join in browser',exact:true}).click();
 await page.getByLabel('Display name').fill('Mike');await page.getByLabel('Email address').fill('mike@example.com');await page.getByRole('button',{name:'Continue with email',exact:true}).click();await visible('Check your email.');assert.equal(sent,1);
 await page.getByLabel('Verification code').fill('000000');await page.getByRole('button',{name:'Verify & continue',exact:true}).click();await visible('Code is invalid or expired.');
 await page.getByLabel('Verification code').fill('123456');await page.getByRole('button',{name:'Verify & continue',exact:true}).click();await visible('Which player are you?');
 await page.getByRole('button',{name:'Guest - Mike',exact:false}).click();await page.getByRole('button',{name:'Request this spot',exact:true}).click();await visible('You’re on the list.');await visible('Guest - Mike');
 game=await rpc(host,'get_game',{p_game_id:game.id});assert.equal(game.claims.length,1);
 await rpc(host,'review_claim',{p_claim_id:game.claims[0].id,p_approve:true});await page.getByRole('button',{name:'Refresh game',exact:true}).click();await visible('Your game.');await visible('Mike');
 await rpc(host,'record_score',{p_game_id:game.id,p_score_a:11,p_score_b:8,p_expected_revision:0});await page.getByRole('button',{name:'Refresh game',exact:true}).click();await visible('YOU LOST');assert.equal((await page.locator('.score').innerText()).replace(/\s/g,''),'8–11');
 await page.getByRole('button',{name:'Confirm this score',exact:true}).click();await visible('✓ You confirmed this score.');await shot('02-result');
 await rpc(host,'record_score',{p_game_id:game.id,p_score_a:11,p_score_b:7,p_expected_revision:1});await page.getByRole('button',{name:'Refresh game',exact:true}).click();await page.getByRole('button',{name:'Confirm this score',exact:true}).waitFor();
 await page.reload();await visible('Your game.');assert.equal(await page.getByRole('button',{name:'Join in browser',exact:true}).count(),0);
 await page.setViewportSize({width:320,height:740});await page.emulateMedia({colorScheme:'dark'});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await shot('03-result-narrow-dark');
 offline=true;await page.getByRole('button',{name:'Refresh game',exact:true}).click();await visible('We couldn’t open this game.');offline=false;await page.getByRole('button',{name:'Try again',exact:true}).click();await visible('Your game.');
 await page.getByRole('button',{name:'Sign out',exact:true}).click();await visible('Cindy invited you.');
 // Account deletion must work without a game token, including the OTP transition.
 await page.goto(origin+'/account/');await visible('Keep your game.');await page.getByLabel('Display name').fill('Mike');await page.getByLabel('Email address').fill('mike@example.com');await page.getByRole('button',{name:'Continue with email',exact:true}).click();await visible('Check your email.');await page.getByLabel('Verification code').fill('123456');await page.getByRole('button',{name:'Verify & continue',exact:true}).click();await visible('Your account.');
 await page.getByLabel('Type DELETE to confirm').fill('DELETE');await page.getByRole('button',{name:'Delete my account permanently',exact:true}).click();await visible('Your account has been deleted.');
 const updated=await rpc(host,'get_game',{p_game_id:game.id});assert.equal(updated.participants[2].account_id,null);assert.equal(updated.participants[2].nickname,'Deleted player');
 await page.goto(origin+'/history/');await visible('Your next game starts with an invitation.');assert.equal(await page.getByRole('heading',{name:'History',exact:true}).count(),0);
 await page.goto(origin+'/join/#'+'f'.repeat(64));await visible('We couldn’t open this game.');
 assert.deepEqual(errors,[]);assert(calls.includes('confirm_score')&&calls.includes('request_spot')&&calls.includes('delete_my_account'));
 console.log('PASS browser: invite, escaped names, OTP errors/retry, host-approved claim, own-team result, confirmation/reset, persisted session, 320px dark layout, connection recovery, standalone account deletion, invalid links, app-only feature boundary.');
}finally{await context.close();await browser.close();await new Promise(r=>server.close(r));await chain;await db.close();}
