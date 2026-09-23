import {writeFile} from 'node:fs/promises';
import {loadEnv} from 'vite';
const env={...loadEnv('production',process.cwd(),''),...process.env};
const team=env.APPLE_TEAM_ID?.trim(),bundle=env.APPLE_BUNDLE_ID?.trim()||'com.versagaldigital.versaquickgame';
if(team&&!/^[A-Z0-9]{10}$/.test(team))throw new Error('APPLE_TEAM_ID must be your 10-character Apple team ID.');
if(!/^[A-Za-z0-9.-]+$/.test(bundle))throw new Error('Invalid Apple bundle identifier.');
const key=env.VITE_SUPABASE_PUBLISHABLE_KEY||'';
if(key.startsWith('sb_secret_'))throw new Error('A secret Supabase key must never be bundled in the website. Use the publishable key.');
if(key.startsWith('eyJ')){
 try{const payload=JSON.parse(Buffer.from(key.split('.')[1],'base64url').toString());if(payload.role!=='anon')throw new Error('Use an anon or publishable key, never a service-role key.');}catch(e){throw new Error('Invalid or unsafe Supabase public key: '+e.message);}
}
await writeFile('public/.well-known/apple-app-site-association',JSON.stringify({applinks:{details:team?[{appIDs:[`${team}.${bundle}`],components:[{'/':'/join/*',comment:'Game invitation links'}]}]:[]}},null,2)+'\n');
if(!team)console.log('Universal links are off until APPLE_TEAM_ID is configured. Browser invitations still work.');
