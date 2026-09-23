import './style.css';
import {liveAPI} from './api';
import type {Game,InvitationAPI} from './types';

const root=document.getElementById('app')!;
const info='https://versagaldigital.com/apps/versaquickgame/';
const demo=import.meta.env.MODE==='demo' && import.meta.env.VITE_DEMO==='true';
const api:InvitationAPI|null=demo?new (await import('./demo')).DemoInvitationAPI():liveAPI();
const accountRoute=location.pathname.replace(/\/$/,'')==='/account';
let token=demo?'demo':location.hash.slice(1);
let game:Game|null=null,authenticated=false,busy=false,error='',notice='',loading=true;
let screen:'invite'|'email'|'verify'|'claim'|'account'=accountRoute?'account':'invite';
let email='',signedInEmail='',displayName='',code='',selected='',deleteText='',lastSent=0;
const esc=(x:unknown)=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const button=(label:string,action:string,secondary=false,disabled=false)=>`<button type="button" class="button${secondary?' secondary':''}" data-action="${action}" ${busy||disabled?'disabled':''}>${label}</button>`;
const validToken=()=>demo||/^[a-f0-9]{64}$/.test(token);
const me=()=>game?.participants.find(p=>p.is_me);
function details(g:Game){return `<section class="details"><span class="badge">${g.score_a===null?'Ready to play':'Game complete'}</span><h2>${esc(g.place)}</h2><p>${g.court?'Court '+esc(g.court):'Court TBD'} · ${esc(new Date(g.starts_at).toLocaleString(undefined,{month:'short',day:'numeric',hour:'numeric',minute:'2-digit'}))}</p><p>${g.game_type==='singles'?'Singles':'Doubles'} · ${g.target} points · ${g.scoring==='sideout'?'Side-out':'Rally'} · Win by ${g.win_by}</p></section>`;}
function teams(g:Game){return `<div class="teams">${[0,1].map(team=>`<section class="team"><h2>TEAM ${team===0?'A':'B'}${me()&&((me()!.slot<2)===(team===0))?' · YOU':''}</h2>${g.participants.filter(p=>(p.slot<2?0:1)===team).map(p=>`<div class="person"><strong>${esc(p.display_name)}</strong><small>${p.slot===0?'Host':p.is_me?'You · Joined':p.claimed?'Joined':'Unclaimed spot'}</small></div>`).join('')}</section>`).join('')}</div>`;}
function login(){
  const verify=screen==='verify';
  return `<div><p class="eyebrow">${accountRoute?'ACCOUNT ACCESS':'SAVE THIS GAME'}</p><h1>${verify?'Check your email.':'Keep your game.'}</h1><p class="sub">${verify?'Enter the verification code sent to '+esc(email)+'.':'Sign in or create an account. No app download needed.'}</p></div>
    <form id="auth-form" class="stack">${verify?`<label>Verification code<input name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6,8}" minlength="6" maxlength="8" required value="${esc(code)}"></label>`:`<label>Display name<input name="displayName" autocomplete="nickname" maxlength="60" required value="${esc(displayName)}"></label><label>Email address<input name="email" type="email" autocomplete="email" required value="${esc(email)}"></label>`}
    <button class="button" type="submit" ${busy?'disabled':''}>${busy?'Please wait…':verify?'Verify & continue':'Continue with email'}</button></form>
    ${verify?`<button class="text-button" data-action="change-email" ${busy?'disabled':''}>Change email / request a new code</button>`:`<p class="note">New accounts use this display name. By continuing, you agree to our <a href="${info}terms/" target="_blank" rel="noopener noreferrer">terms</a> and acknowledge our <a href="${info}privacy/" target="_blank" rel="noopener noreferrer">privacy policy</a>.</p>`}
    ${!accountRoute?'<button class="text-button" data-action="back">Back to invitation</button>':''}`;
}
function claim(){
  if(!game)return '';
  return `<div><p class="eyebrow">CHOOSE YOUR SPOT</p><h1>Which player are you?</h1><p class="sub">Pick the nickname ${esc(game.host_name)} entered for you.</p></div>
    ${game.my_claim?.status==='declined'?'<p class="notice">Your previous request was declined. Check your spot with the host before requesting again.</p>':''}
    <div class="stack">${game.participants.filter(p=>!p.claimed&&p.slot>0).map(p=>`<button class="choice" data-spot="${esc(p.id)}" aria-pressed="${selected===p.id}" ${busy?'disabled':''}><span><strong>${esc(p.display_name)}</strong><small>Team ${p.slot<2?'A · With '+esc(game!.host_name):'B'}</small></span><span class="radio" aria-hidden="true"></span></button>`).join('')||'<p class="notice">Every spot has been claimed. Ask the host to check the game.</p>'}</div>
    ${button('Request this spot','request',false,!selected)}<p class="note center">The host will confirm that this is your spot.</p><button class="text-button" data-action="back">Back to invitation</button>`;
}
function invitation(){
  if(!game)return '';
  const person=me(),pending=game.my_claim?.status==='pending',complete=game.score_a!==null;
  let body=`<div><h1>${person?'Your game.':pending?'You’re on the list.':esc(game.host_name)+' invited you.'}</h1><p class="sub">${person?'Your spot is connected to your account.':pending?'Go ahead and play. The host will confirm your spot.':'Claim your spot and keep the result.'}</p></div>`;
  if(person&&complete){
    const own=person.slot<2?game.score_a!:game.score_b!,opponent=person.slot<2?game.score_b!:game.score_a!;
    body+=`<section class="scoreboard"><span class="badge">${own>opponent?'YOU WON':'YOU LOST'}</span><p class="score">${own} <span>–</span> ${opponent}</p><p>${game.game_type==='singles'?'You · Opponent':'Your team · Opponents'}</p></section>`;
  }
  body+=details(game)+teams(game);
  if(person){
    body+=complete?`<p class="notice">${game.confirmed_by_me?'✓ You confirmed this score.':'Recorded by '+esc(game.host_name)+'. Please check the score.'}</p>${!game.confirmed_by_me&&person.slot!==0?button('Confirm this score','confirm'):''}`:'<p class="notice">Spot confirmed. Waiting for the final score.</p>';
    body+='<p class="note center">Return to this invitation link to see your result.</p>';
  }else if(pending){
    body+='<p class="notice">Your request is waiting for host approval. Your name stays a guest until it is approved.</p>';
  }else{
    body+=button(authenticated?'Claim your spot':'Join in browser','join')+'<p class="note center">No app download needed.</p>';
  }
  if(person||pending)body+='<button class="text-button" data-action="refresh">Refresh game</button>';
  body+=`<button class="text-button" data-action="open-app">Have the app? Open this game</button><p class="note center">Joining is optional. Everyone can play.</p>`;
  return body;
}
function account(){
  if(!authenticated)return login();
  return `<div><p class="eyebrow">ACCOUNT</p><h1>Your account.</h1><p class="sub">${esc(signedInEmail)}</p></div><section class="details"><h2>Delete account</h2><p>This permanently deletes your account, hosted games, clubs, and groups. Your claimed spots in other hosts’ games become anonymous. This cannot be undone.</p></section><form id="delete-form" class="stack"><label>Type DELETE to confirm<input name="deleteText" autocomplete="off" pattern="DELETE" required value="${esc(deleteText)}"></label><button class="button danger" type="submit" ${busy?'disabled':''}>Delete my account permanently</button></form>${button('Sign out','signout',true)}${validToken()?'<button class="text-button" data-action="back">Back to invitation</button>':''}`;
}
function render(){
  let body='';
  if(loading)body='<div class="empty"><div class="spinner" aria-hidden="true"></div><h1>Opening your game…</h1></div>';
  else if(!api)body=`<div class="empty"><h1>Invitations are coming soon.</h1><p>The invitation service is being prepared. Please check with your host.</p><a class="button" href="${info}">About Versa Quick Game</a></div>`;
  else if(screen==='account')body=account();
  else if(screen==='email'||screen==='verify')body=login();
  else if(!validToken())body=`<div class="empty"><h1>Your next game starts with an invitation.</h1><p>Open the link or scan the QR code shared by your host.</p><a class="button" href="${info}">About Versa Quick Game</a></div>`;
  else if(!game)body=`<div class="empty"><h1>We couldn’t open this game.</h1><p>Check your connection, or ask your host for a fresh invitation.</p>${button('Try again','refresh',true)}</div>`;
  else if(screen==='claim')body=claim();
  else body=invitation();
  root.innerHTML=`${demo?'<aside class="demo-banner">DEMO · Fictional game · Email code: 123456</aside>':''}<div class="shell"><header><img src="/icon-192.png" width="38" height="38" alt=""><strong>Versa Quick Game</strong><span class="header-label">${authenticated?'SIGNED IN':'INVITE'}</span></header><main aria-busy="${busy}">${error?`<p class="error" role="alert">${esc(error)}</p>`:''}${notice?`<p class="notice" role="status">${esc(notice)}</p>`:''}${body}</main>
    <footer><a href="${info}support/" target="_blank" rel="noopener noreferrer">Support</a><a href="${info}privacy/" target="_blank" rel="noopener noreferrer">Privacy</a><a href="${info}terms/" target="_blank" rel="noopener noreferrer">Terms</a>${authenticated?'<button class="text-button" data-action="account">Account</button>':''}<p>By VersaGal Digital</p>${authenticated?`<p class="signed-in">${esc(signedInEmail)} · <button class="text-button" data-action="signout">Sign out</button></p>`:''}</footer></div>
    ${demo&&game?.my_claim?.status==='pending'?'<div class="demo-actions"><button data-action="demo-approve">Preview host approval</button></div>':''}
    ${demo&&me()&&game?.score_a===null?'<div class="demo-actions"><button data-action="demo-result">Preview host recording 11–8</button></div>':''}`;
}
async function refresh(silent=false){
  if(!api||!validToken())return;
  try{
    const updated=await api.getInvitation(token);
    const changed=JSON.stringify(updated)!==JSON.stringify(game);
    game=updated;
    if(me()||game.my_claim?.status==='pending')screen='invite';
    if(!silent)error='';
    if(changed||!silent)render();
  }catch(e){if(!silent){game=null;error=message(e);render();}}
}
function message(e:unknown){return e instanceof Error?e.message:'Something went wrong. Please try again.';}
async function run(work:()=>Promise<void>){if(busy)return;busy=true;error='';notice='';render();try{await work();}catch(e){error=message(e);}finally{busy=false;render();}}

root.addEventListener('input',event=>{
  const input=event.target as HTMLInputElement;
  switch(input.name){case 'displayName':displayName=input.value;break;case 'email':email=input.value;break;case 'code':code=input.value;break;case 'deleteText':deleteText=input.value;break;}
});
root.addEventListener('submit',event=>{
  event.preventDefault();if(!api)return;
  const form=event.target as HTMLFormElement;
  if(form.id==='auth-form')void run(async()=>{
    if(screen==='verify'){
      await api.verifyCode(email.trim(),code.trim(),displayName.trim());authenticated=true;signedInEmail=await api.accountEmail()??email;
      screen=accountRoute?'account':'claim';if(validToken())await refresh();
    }else{
      if(!displayName.trim())throw new Error('Enter a display name.');
      if(Date.now()-lastSent<60000)throw new Error('Please wait a minute before requesting another code.');
      await api.sendCode(email.trim(),displayName.trim());lastSent=Date.now();screen='verify';
    }
  });
  if(form.id==='delete-form')void run(async()=>{
    if(deleteText!=='DELETE')throw new Error('Type DELETE to confirm.');
    await api.deleteAccount();authenticated=false;signedInEmail='';deleteText='';notice='Your account has been deleted.';
    screen=accountRoute?'account':'invite';if(validToken())await refresh();
  });
});
root.addEventListener('click',event=>{
  const target=(event.target as HTMLElement).closest<HTMLButtonElement>('button');if(!target||target.disabled||!api)return;
  if(target.dataset.spot){selected=target.dataset.spot;render();return;}
  switch(target.dataset.action){
    case 'join':screen=authenticated?'claim':'email';error='';render();break;
    case 'back':screen='invite';error='';notice='';render();break;
    case 'account':screen='account';error='';render();break;
    case 'change-email':screen='email';code='';error='';render();break;
    case 'refresh':void run(()=>refresh());break;
    case 'request':void run(async()=>{game=await api.requestSpot(token,selected);screen='invite';});break;
    case 'confirm':void run(async()=>{if(game)game=await api.confirmScore(game.id,game.revision);});break;
    case 'signout':void run(async()=>{await api.signOut();authenticated=false;signedInEmail='';screen=accountRoute?'account':'invite';if(validToken())await refresh();});break;
    case 'open-app':
      if(demo){notice='Demo only. A real invitation opens the installed iPhone app.';render();}
      else{location.href='versaquickgame://join?token='+encodeURIComponent(token);notice='If the app did not open, you can continue in this browser.';render();}
      break;
    case 'demo-approve':api.demoApprove?.();void refresh();break;
    case 'demo-result':api.demoResult?.();void refresh();break;
  }
});
window.addEventListener('hashchange',()=>{if(demo)return;token=location.hash.slice(1);game=null;selected='';screen='invite';error='';void refresh();render();});
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&screen==='invite'&&!busy)void refresh(true);});
setInterval(()=>{if(!document.hidden&&!busy&&screen==='invite'&&(game?.my_claim?.status==='pending'||me()))void refresh(true);},12000);
render();
try{
  if(api){authenticated=await api.signedIn();signedInEmail=await api.accountEmail()??'';if(validToken())game=await api.getInvitation(token);}
}catch(e){error=message(e);}
finally{loading=false;render();}
