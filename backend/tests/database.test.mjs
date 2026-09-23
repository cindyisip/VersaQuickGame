import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

let db,game,token,annaClaim,mikeClaim;
const host='00000000-0000-4000-8000-000000000001',anna='00000000-0000-4000-8000-000000000002',mike='00000000-0000-4000-8000-000000000003',stranger='00000000-0000-4000-8000-000000000004';
async function as(id,sql,args=[]){
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);
 await db.exec(id?'set role authenticated':'set role anon');
 return db.query(sql,args);
}
async function rpc(id,sql,args=[]){return (await as(id,sql,args)).rows[0].result;}
before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb default '{}'::jsonb);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema public,auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 await db.exec(await readFile(new URL('../migrations/202609230001_initial.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../migrations/202609230002_opponent_periods.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../migrations/202609230003_teammate_periods.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../migrations/202609230004_shared_groups.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../migrations/202609230005_singles.sql',import.meta.url),'utf8'));
 for(const [id,name] of [[host,'Cindy'],[anna,'Anna'],[mike,'Mike'],[stranger,'Other person']]){
  await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({display_name:name})]);
  await rpc(id,'select public.bootstrap() result');await db.exec('reset role');
 }
});
after(async()=>await db.close());
test('Private tables and host functions cannot be accessed anonymously',async()=>{
 await assert.rejects(as(null,'select * from private.games'),/permission denied/);
 await assert.rejects(as(null,'select public.bootstrap()'),/permission denied/);
});
test('Club names are per owner and default club cannot be stolen from another user',async()=>{
 let data=await rpc(host,'select public.add_club($1) result',['HUB Silicon Valley']);
 const id=data.clubs[0].id;
 data=await rpc(host,'select public.add_club($1) result',[' hub silicon valley ']);assert.equal(data.clubs.length,1);
 await assert.rejects(as(anna,'select public.save_profile($1,$2)',['Anna',id]),/your saved clubs/);
 data=await rpc(host,'select public.save_profile($1,$2) result',['Cindy',id]);assert.equal(data.profile.default_club_id,id);
});
test('Game creation is atomic, permits outsiders, retains guest identity, and is idempotent',async()=>{
 const args=['HUB Silicon Valley','3','2026-09-23T17:30:00-07:00',11,'sideout',2,JSON.stringify([{nickname:'Anna'},{nickname:'Mike'},{nickname:'Jo'}]),'11111111-1111-4111-8111-111111111111'];
 const sql='select public.create_game($1,$2,$3,$4,$5,$6,$7,$8) result';
 game=await rpc(host,sql,args);
 assert.equal(game.participants.length,4);assert.equal(game.participants[1].display_name,'Guest - Anna');
 const retry=await rpc(host,sql,args);assert.equal(retry.id,game.id);
 await assert.rejects(as(stranger,sql,args),/Request ID unavailable/);
 token=(await rpc(host,'select public.get_invite_link($1) result',[game.id])).token;assert.match(token,/^[a-f0-9]{64}$/);
});
test('Invitation exposes only this game and no user IDs or email addresses',async()=>{
 const invite=await rpc(null,'select public.get_invitation($1) result',[token]);
 assert.equal(invite.host_id,undefined);assert.equal(invite.participants[0].account_id,undefined);
 assert.equal(invite.participants[1].pool_player_id,undefined);assert.deepEqual(invite.claims,[]);
 await assert.rejects(as(null,'select public.get_invitation($1)',['made-up']),/unavailable/);
 await assert.rejects(as(stranger,'select public.get_game($1)',[game.id]),/access denied/);
 await assert.rejects(as(stranger,'select public.get_invite_link($1)',[game.id]),/Only the host/);
});
test('Unapproved claims cannot read private games or alter a score',async()=>{
 let invite=await rpc(anna,'select public.request_spot($1,$2) result',[token,game.participants[1].id]);annaClaim=invite.my_claim.id;
 assert.equal(invite.participants[1].display_name,'Guest - Anna');
 await assert.rejects(as(anna,'select public.get_game($1)',[game.id]),/access denied/);
 await assert.rejects(as(anna,'select public.record_score($1,11,8,0)',[game.id]),/Only the host/);
 await assert.rejects(as(anna,'select public.review_claim($1,true)',[annaClaim]),/Only the host/);
});
test('Approval links only the chosen spot and rejects a second claim on an occupied spot',async()=>{
 game=await rpc(host,'select public.review_claim($1,true) result',[annaClaim]);
 assert.equal(game.participants[1].display_name,'Anna');assert.equal(game.participants[2].display_name,'Guest - Mike');
 await assert.rejects(as(mike,'select public.request_spot($1,$2)',[token,game.participants[1].id]),/no longer available/);
 await assert.rejects(as(anna,'select public.request_spot($1,$2)',[token,game.participants[2].id]),/already have a spot/);
 const invite=await rpc(mike,'select public.request_spot($1,$2) result',[token,game.participants[2].id]);mikeClaim=invite.my_claim.id;
 game=await rpc(host,'select public.review_claim($1,true) result',[mikeClaim]);
});
test('Scores enforce format and revision, and confirmation is distinct from claiming',async()=>{
 await assert.rejects(as(host,'select public.record_score($1,11,10,0)',[game.id]),/completed score/);
 await assert.rejects(as(host,'select public.record_score($1,12,8,0)',[game.id]),/completed score/);
 game=await rpc(host,'select public.record_score($1,11,8,0) result',[game.id]);assert.equal(game.revision,1);assert.equal(game.confirmation_count,0);
 await assert.rejects(as(host,'select public.record_score($1,11,7,0)',[game.id]),/score changed/);
 await assert.rejects(as(stranger,'select public.confirm_score($1,1)',[game.id]),/joined player/);
 game=await rpc(anna,'select public.confirm_score($1,1) result',[game.id]);assert.equal(game.confirmed_by_me,true);
 game=await rpc(host,'select public.record_score($1,11,7,1) result',[game.id]);assert.equal(game.confirmation_count,0);
 await assert.rejects(as(anna,'select public.confirm_score($1,1)',[game.id]),/score changed/);
});
test('Summary uses each account’s team, includes with/against, ignores history filters',async()=>{
 const hostSummary=await rpc(host,'select public.get_summary() result');assert.equal(hostSummary.overall.wins,1);assert.equal(hostSummary.overall.win_percent,100);
 const mikeSummary=await rpc(mike,'select public.get_summary() result');assert.equal(mikeSummary.overall.losses,1);assert.equal(mikeSummary.overall.loss_percent,100);
 const annaKey=hostSummary.people.find(p=>p.name==='Anna').key;
 const detail=await rpc(host,'select public.get_summary($1) result',[annaKey]);assert.equal(detail.with_player.games,1);assert.equal(detail.against_player.games,0);
 const filtered=await rpc(host,"select public.list_games('2027-01-01',null,'',0) result");assert.deepEqual(filtered,[]);
 assert.equal((await rpc(host,'select public.get_summary() result')).overall.games,1);
 assert.equal((await rpc(stranger,'select public.get_summary() result')).overall.games,0);
});
test('One selected period compares both teammate and opponent results while overall stays all-time',async()=>{
 const originalKey=(await rpc(host,'select public.get_summary() result')).people.find(p=>p.name==='Anna').key;
 const poolID=game.participants[1].pool_player_id;
 for(const [date,scoreA,scoreB,requestID,asPartner] of [
  ['2026-08-10T19:00:00Z',8,11,'22222222-2222-4222-8222-222222222222',false],
  ['2025-09-20T19:00:00Z',11,7,'33333333-3333-4333-8333-333333333333',false],
  ['2026-08-11T19:00:00Z',8,11,'44444444-4444-4444-8444-444444444444',true],
  ['2025-09-21T19:00:00Z',11,9,'55555555-5555-4555-8555-555555555555',true]]){
  const playerList=JSON.stringify(asPartner?
   [{nickname:'Anna',player_id:poolID},{nickname:'Pat'},{nickname:'Jo'}]:
   [{nickname:'Pat'},{nickname:'Anna',player_id:poolID},{nickname:'Jo'}]);
  const created=await rpc(host,'select public.create_game($1,$2,$3,$4,$5,$6,$7,$8) result',
   ['HUB Silicon Valley','2',date,11,'sideout',2,playerList,requestID]);
  await rpc(host,'select public.record_score($1,$2,$3,0) result',[created.id,scoreA,scoreB]);
 }
 const withSQL='select public.get_teammate_stats($1,$2,$3) result';
 const againstSQL='select public.get_opponent_stats($1,$2,$3) result';
 const windows=[['2026-09-01T00:00:00Z','2026-10-01T00:00:00Z'],
                ['2026-08-01T00:00:00Z','2026-09-01T00:00:00Z'],
                ['2025-09-01T00:00:00Z','2025-10-01T00:00:00Z']];
 const expectedWith=[[1,1,0],[1,0,1],[1,1,0]];
 const expectedAgainst=[[0,0,0],[1,0,1],[1,1,0]];
 for(const [i,[from,until]] of windows.entries()){
  const withPlayer=await rpc(host,withSQL,[originalKey,from,until]);
  const againstPlayer=await rpc(host,againstSQL,[originalKey,from,until]);
  assert.deepEqual([withPlayer.games,withPlayer.wins,withPlayer.losses],expectedWith[i]);
  assert.deepEqual([againstPlayer.games,againstPlayer.wins,againstPlayer.losses],expectedAgainst[i]);
 }
 const all=await rpc(host,'select public.get_summary($1) result',[originalKey]);
 assert.equal(all.overall.games,5);assert.equal(all.with_player.games,3);assert.equal(all.against_player.games,2);
 await assert.rejects(as(null,withSQL,[originalKey,null,null]),/permission denied/);
 await assert.rejects(as(host,withSQL,[originalKey,'2026-10-01','2026-09-01']),/Invalid teammate or date range/);
 assert.equal((await rpc(stranger,withSQL,[originalKey,null,null])).games,0);
});
test('Groups accept overlapping memberships and never restrict game creation',async()=>{
 const player=await rpc(host,'select public.add_player($1) result',['Pat']);
 await rpc(host,'select public.save_group($1,$2) result',['Tuesday Group',[player.id]]);
 const data=await rpc(host,'select public.save_group($1,$2) result',['Pinoy Group',[player.id]]);assert.equal(data.groups.length,2);
 await assert.rejects(as(anna,'select public.save_group($1,$2)',['Other',[player.id]]),/your player pool/);
});
test('Shared groups require an invitation and dynamically filter scored games by claimed members',async()=>{
 let groups=await rpc(host,"select public.create_shared_group('Tuesday','one_each') result");
 const groupID=groups[0].id;
 await assert.rejects(as(stranger,'select public.get_shared_group_board($1)',[groupID]),/Group unavailable/);
 let board=await rpc(host,'select public.get_shared_group_board($1) result',[groupID]);assert.equal(board.games.length,0);
 const invite=await rpc(host,'select public.get_shared_group_invite($1) result',[groupID]);
 await assert.rejects(as(null,'select public.join_shared_group($1)',[invite]),/permission denied/);
 groups=await rpc(mike,'select public.join_shared_group($1) result',[invite]);assert.equal(groups[0].members.length,2);
 board=await rpc(host,'select public.get_shared_group_board($1) result',[groupID]);
 assert.equal(board.games.length,1);assert.equal(board.leaders.find(x=>x.name==='Cindy').wins,1);
 assert.equal(board.leaders.find(x=>x.name==='Mike').losses,1);
 await assert.rejects(as(mike,"select public.set_shared_group_rule($1,'all_players')",[groupID]),/group creator/);
 await rpc(host,"select public.set_shared_group_rule($1,'all_players') result",[groupID]);
 board=await rpc(mike,'select public.get_shared_group_board($1) result',[groupID]);assert.equal(board.games.length,0);
 await rpc(anna,'select public.join_shared_group($1) result',[invite]);
 board=await rpc(host,'select public.get_shared_group_board($1) result',[groupID]);assert.equal(board.games.length,0);
 const single=await rpc(host,'select public.create_game($1,$2,$3,$4,$5,$6,$7,$8) result',
  ['HUB Silicon Valley','2','2026-09-23T18:00:00Z',11,'sideout',2,JSON.stringify([{nickname:'Anna'}]),'66666666-6666-4666-8666-666666666666']);
 assert.equal(single.game_type,'singles');assert.deepEqual(single.participants.map(p=>p.slot),[0,2]);
 const singleInvite=(await rpc(host,'select public.get_invite_link($1) result',[single.id])).token;
 const claim=await rpc(anna,'select public.request_spot($1,$2) result',[singleInvite,single.participants[1].id]);
 await rpc(host,'select public.review_claim($1,true) result',[claim.my_claim.id]);
 await rpc(host,'select public.record_score($1,11,7,0) result',[single.id]);
 board=await rpc(host,"select public.get_shared_group_board($1,'singles') result",[groupID]);
 assert.equal(board.games.length,1);assert.equal(board.leaders.find(x=>x.name==='Cindy').wins,1);
 const doubles=await rpc(host,"select public.get_shared_group_board($1,'players') result",[groupID]);
 assert.equal(doubles.games.length,0);assert.equal(doubles.leaders.length,0);
});
test('Revoking invitation blocks new guests but approved players retain their result',async()=>{
 const active=await rpc(host,'select public.get_invite_link($1) result',[game.id]);assert.equal(active.expires_at,null);
 await rpc(host,'select public.revoke_invite($1) result',[game.id]);
 await assert.rejects(as(null,'select public.get_invitation($1)',[token]),/was closed/);
 assert.equal((await rpc(anna,'select public.get_invitation($1) result',[token])).id,game.id);
 const renewed=await rpc(host,'select public.get_invite_link($1,true) result',[game.id]);assert.notEqual(renewed.token,token);
 token=renewed.token;assert.equal((await rpc(null,'select public.get_invitation($1) result',[token])).id,game.id);
});
test('Deleting an account removes identity in shared games and prevents subsequent authenticated access',async()=>{
 await assert.rejects(as(anna,'select public.delete_my_account($1)',['no']),/Type DELETE/);
 await rpc(anna,"select public.delete_my_account('DELETE') result");
 const result=await rpc(host,'select public.get_game($1) result',[game.id]);
 assert.equal(result.participants[1].account_id,null);assert.equal(result.participants[1].nickname,'Deleted player');
 await assert.rejects(as(anna,'select public.bootstrap()'),/Sign in to continue/);
});
