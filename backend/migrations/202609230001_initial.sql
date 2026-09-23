-- Versa Quick Game 0.1. Run in a new Supabase project using the SQL editor or CLI.
-- Private tables are not exposed by the Data API. Only the narrow public RPCs below are callable.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 60),
  default_club_id uuid,
  created_at timestamptz not null default now()
);
create table private.clubs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references private.profiles(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  created_at timestamptz not null default now()
);
create unique index clubs_owner_name on private.clubs(owner_id, lower(btrim(name)));
alter table private.profiles add constraint profile_default_club foreign key(default_club_id) references private.clubs(id) on delete set null;
create table private.players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references private.profiles(id) on delete cascade,
  nickname text not null check (length(btrim(nickname)) between 1 and 60),
  created_at timestamptz not null default now()
);
create table private.player_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references private.profiles(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 60)
);
create table private.group_members (
  group_id uuid not null references private.player_groups(id) on delete cascade,
  player_id uuid not null references private.players(id) on delete cascade,
  primary key(group_id, player_id)
);
create table private.games (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references private.profiles(id) on delete cascade,
  place text not null check(length(btrim(place)) between 1 and 120),
  court text not null default '' check(length(court)<=20),
  starts_at timestamptz not null,
  target integer not null default 11 check(target in(11,15,21)),
  scoring text not null default 'sideout' check(scoring in('sideout','rally')),
  win_by integer not null default 2 check(win_by in(1,2)),
  score_a integer check(score_a between 0 and 99),
  score_b integer check(score_b between 0 and 99),
  revision integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((score_a is null) = (score_b is null))
);
create index games_host_date on private.games(host_id, starts_at desc);
create table private.game_players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references private.games(id) on delete cascade,
  slot integer not null check(slot between 0 and 3),
  pool_player_id uuid references private.players(id) on delete set null,
  nickname text not null check(length(btrim(nickname)) between 1 and 60),
  account_id uuid references private.profiles(id) on delete set null,
  unique(game_id,slot), unique(game_id,account_id)
);
create index game_players_account on private.game_players(account_id,game_id);
create table private.invites (
  game_id uuid primary key references private.games(id) on delete cascade,
  token text not null unique default(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','')),
  expires_at timestamptz not null default(now()+interval '30 days'),
  revoked boolean not null default false
);
create table private.claims (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references private.games(id) on delete cascade,
  participant_id uuid not null references private.game_players(id) on delete cascade,
  requester_id uuid not null references private.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in('pending','approved','declined')),
  created_at timestamptz not null default now(),
  unique(game_id,requester_id)
);
create table private.confirmations (
  game_id uuid not null references private.games(id) on delete cascade,
  account_id uuid not null references private.profiles(id) on delete cascade,
  revision integer not null,
  confirmed_at timestamptz not null default now(),
  primary key(game_id,account_id)
);
create table private.score_changes (
  id bigint generated always as identity primary key,
  game_id uuid not null references private.games(id) on delete cascade,
  revision integer not null,
  score_a integer not null,
  score_b integer not null,
  recorded_at timestamptz not null default now()
);

-- No direct read/write policies: all access is through permission-checked functions.
do $$ declare t text; begin
  foreach t in array array['profiles','clubs','players','player_groups','group_members','games','game_players','invites','claims','confirmations','score_changes'] loop
    execute format('alter table private.%I enable row level security',t);
    execute format('revoke all on private.%I from public, anon, authenticated',t);
  end loop;
end $$;

create function private.require_user() returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); begin
  if u is null or not exists(select 1 from auth.users where id=u) then raise exception 'Sign in to continue' using errcode='28000'; end if;
  return u;
end $$;
create function private.can_read_game(g uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.game_players where game_id=g and account_id=auth.uid());
$$;
create function private.game_json(g uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
   'id',x.id,'host_id',x.host_id,'host_name',p.display_name,'place',x.place,'court',x.court,
   'starts_at',x.starts_at,'target',x.target,'scoring',x.scoring,'win_by',x.win_by,
   'score_a',x.score_a,'score_b',x.score_b,'revision',x.revision,'updated_at',x.updated_at,
   'participants',coalesce((select jsonb_agg(jsonb_build_object(
     'id',gp.id,'slot',gp.slot,'pool_player_id',gp.pool_player_id,'nickname',gp.nickname,
     'display_name',case when gp.account_id is null then 'Guest - '||gp.nickname else coalesce(pr.display_name,'Deleted player') end,
     'account_id',gp.account_id,'is_me',coalesce(gp.account_id=auth.uid(),false),'claimed',gp.account_id is not null,
     'peer_key',coalesce('pool:'||gp.pool_player_id::text,'user:'||gp.account_id::text,'slot:'||gp.id::text)
   ) order by gp.slot) from private.game_players gp left join private.profiles pr on pr.id=gp.account_id where gp.game_id=x.id),'[]'::jsonb),
   'claims',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'participant_id',c.participant_id,'requester_name',cp.display_name,'status',c.status))
     from private.claims c join private.profiles cp on cp.id=c.requester_id where c.game_id=x.id and c.status='pending' and x.host_id=auth.uid()),'[]'::jsonb),
   'my_claim',(select jsonb_build_object('id',c.id,'participant_id',c.participant_id,'status',c.status) from private.claims c where c.game_id=x.id and c.requester_id=auth.uid()),
   'confirmed_by_me',exists(select 1 from private.confirmations f where f.game_id=x.id and f.account_id=auth.uid() and f.revision=x.revision),
   'confirmation_count',(select count(*) from private.confirmations f where f.game_id=x.id and f.revision=x.revision)
 ) from private.games x join private.profiles p on p.id=x.host_id where x.id=g;
$$;

create function public.bootstrap(p_display_name text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); n text; begin
  n:=coalesce(nullif(btrim(p_display_name),''),(select nullif(btrim(raw_user_meta_data->>'display_name'),'') from auth.users where id=u),'Player');
  if length(n)>60 then raise exception 'Use a display name of 60 characters or fewer'; end if;
  insert into private.profiles(id,display_name) values(u,n) on conflict(id) do nothing;
  return jsonb_build_object(
   'profile',(select to_jsonb(p) from private.profiles p where p.id=u),
   'clubs',coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from private.clubs c where c.owner_id=u),'[]'::jsonb),
   'players',coalesce((select jsonb_agg(to_jsonb(p) order by p.nickname,p.id) from private.players p where p.owner_id=u),'[]'::jsonb),
   'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'member_ids',coalesce((select jsonb_agg(m.player_id) from private.group_members m where m.group_id=g.id),'[]'::jsonb)) order by g.name) from private.player_groups g where g.owner_id=u),'[]'::jsonb)
  );
end $$;
create function public.save_profile(p_display_name text,p_default_club_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); begin
 if p_display_name is null or length(btrim(p_display_name)) not between 1 and 60 then raise exception 'Enter a display name (1–60 characters)'; end if;
 if p_default_club_id is not null and not exists(select 1 from private.clubs where id=p_default_club_id and owner_id=u) then raise exception 'Choose one of your saved clubs'; end if;
 update private.profiles set display_name=btrim(p_display_name),default_club_id=p_default_club_id where id=u;
 return public.bootstrap();
end $$;
create function public.add_club(p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); begin
 if p_name is null or length(btrim(p_name)) not between 1 and 120 then raise exception 'Enter a club name (1–120 characters)'; end if;
 insert into private.clubs(owner_id,name) values(u,btrim(p_name)) on conflict do nothing;
 return public.bootstrap();
end $$;
create function public.add_player(p_nickname text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); p private.players; begin
 if p_nickname is null or length(btrim(p_nickname)) not between 1 and 60 then raise exception 'Enter a nickname (1–60 characters)'; end if;
 insert into private.players(owner_id,nickname) values(u,btrim(p_nickname)) returning * into p;
 return to_jsonb(p);
end $$;
create function public.save_group(p_name text,p_player_ids uuid[],p_group_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g uuid:=p_group_id; begin
 if p_name is null or length(btrim(p_name)) not between 1 and 60 then raise exception 'Enter a group name (1–60 characters)'; end if;
 if cardinality(p_player_ids)>500 then raise exception 'A group can contain up to 500 players'; end if;
 if exists(select 1 from unnest(p_player_ids) t(id) where not exists(select 1 from private.players p where p.id=t.id and p.owner_id=u)) then raise exception 'Choose players from your player pool'; end if;
 if g is null then insert into private.player_groups(owner_id,name) values(u,btrim(p_name)) returning id into g;
 else
   if not exists(select 1 from private.player_groups where id=g and owner_id=u) then raise exception 'Group not found'; end if;
   update private.player_groups set name=btrim(p_name) where id=g;
 end if;
 delete from private.group_members where group_id=g;
 insert into private.group_members select g,id from (select distinct unnest(p_player_ids) id) q;
 return public.bootstrap();
end $$;

create function public.create_game(p_place text,p_court text,p_starts_at timestamptz,p_target integer,p_scoring text,p_win_by integer,p_players jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g uuid; item jsonb; pid uuid; n text; s integer:=1; begin
 if not exists(select 1 from private.profiles where id=u) then raise exception 'Finish setting up your account'; end if;
 if p_request_id is null then raise exception 'Missing request ID'; end if;
 -- The client retains a UUID across retries, so a network retry cannot create a duplicate game.
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 if exists(select 1 from private.games where id=p_request_id) then
   if not exists(select 1 from private.games where id=p_request_id and host_id=u) then raise exception 'Request ID unavailable'; end if;
   return private.game_json(p_request_id);
 end if;
 if p_place is null or length(btrim(p_place)) not between 1 and 120 or p_starts_at is null then raise exception 'Choose a place and time'; end if;
 if p_target is null or p_target not in(11,15,21) or p_win_by is null or p_win_by not in(1,2) or p_scoring is null or p_scoring not in('sideout','rally') then raise exception 'Unsupported game format'; end if;
 if jsonb_typeof(p_players) is distinct from 'array' or jsonb_array_length(p_players)<>3 then raise exception 'Add three other players'; end if;
 insert into private.games(id,host_id,place,court,starts_at,target,scoring,win_by) values(p_request_id,u,btrim(p_place),btrim(coalesce(p_court,'')),p_starts_at,p_target,p_scoring,p_win_by) returning id into g;
 insert into private.game_players(game_id,slot,nickname,account_id) select g,0,display_name,u from private.profiles where id=u;
 for item in select value from jsonb_array_elements(p_players) loop
   pid:=nullif(item->>'player_id','')::uuid;
   if pid is not null then
     select nickname into n from private.players where id=pid and owner_id=u;
     if not found then raise exception 'Player is not in your pool'; end if;
     if exists(select 1 from private.game_players where game_id=g and pool_player_id=pid) then raise exception 'Each spot needs a different player'; end if;
   else
     n:=btrim(item->>'nickname');
     if n is null or length(n) not between 1 and 60 then raise exception 'Enter each player’s nickname'; end if;
     insert into private.players(owner_id,nickname) values(u,n) returning id into pid;
   end if;
   insert into private.game_players(game_id,slot,pool_player_id,nickname) values(g,s,pid,n);
   s:=s+1;
 end loop;
 insert into private.invites(game_id) values(g);
 return private.game_json(g);
end $$;
create function public.get_game(p_game_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 if not private.can_read_game(p_game_id) then raise exception 'Game not found or access denied'; end if;
 return private.game_json(p_game_id);
end $$;
create function public.get_invite_link(p_game_id uuid,p_rotate boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); begin
 if not exists(select 1 from private.games where id=p_game_id and host_id=u) then raise exception 'Only the host can share this game'; end if;
 if p_rotate then update private.invites set token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),expires_at=now()+interval '30 days',revoked=false where game_id=p_game_id; end if;
 return (select jsonb_build_object('token',token,'expires_at',expires_at,'revoked',revoked) from private.invites where game_id=p_game_id);
end $$;
create function public.revoke_invite(p_game_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from private.games where id=p_game_id and host_id=private.require_user()) then raise exception 'Only the host can stop invitations'; end if;
 update private.invites set revoked=true where game_id=p_game_id;
end $$;
create function private.invited_game(t text,for_claim boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare i private.invites; begin
 if t is null or t !~ '^[0-9a-f]{64}$' then raise exception 'This invitation is unavailable'; end if;
 select * into i from private.invites where token=t;
 if not found then raise exception 'This invitation is unavailable'; end if;
 if i.revoked or i.expires_at<=now() then
   if for_claim or not private.can_read_game(i.game_id) then raise exception 'This invitation has expired or was closed. Ask the host for a new link.'; end if;
 end if;
 return i.game_id;
end $$;
create function public.get_invitation(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare g uuid:=private.invited_game(p_token); j jsonb; begin
 j:=private.game_json(g);
 -- Invitation viewers get no account UUIDs, private pool IDs, or claim-request identities.
 if not private.can_read_game(g) then
   j:=j-'host_id';
   j:=jsonb_set(j,'{participants}',(select jsonb_agg(x-'account_id'-'pool_player_id'-'peer_key') from jsonb_array_elements(j->'participants') x));
 end if;
 return j;
end $$;
create function public.request_spot(p_token text,p_participant_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g uuid:=private.invited_game(p_token,true); gp private.game_players; begin
 perform 1 from private.games where id=g for update;
 if exists(select 1 from private.game_players where game_id=g and account_id=u) then raise exception 'You already have a spot in this game'; end if;
 select * into gp from private.game_players where id=p_participant_id and game_id=g and slot>0 for update;
 if not found or gp.account_id is not null then raise exception 'This spot is no longer available'; end if;
 insert into private.claims(game_id,participant_id,requester_id) values(g,gp.id,u)
 on conflict(game_id,requester_id) do update set participant_id=excluded.participant_id,status='pending',created_at=now();
 return public.get_invitation(p_token);
end $$;
create function public.review_claim(p_claim_id uuid,p_approve boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); c private.claims; g uuid; begin
 select game_id into g from private.claims where id=p_claim_id;
 perform 1 from private.games where id=g and host_id=u for update;
 if not found then raise exception 'Only the host can review this request'; end if;
 select * into c from private.claims where id=p_claim_id for update;
 if c.status<>'pending' then raise exception 'This request has already been reviewed'; end if;
 if p_approve is null then raise exception 'Choose approve or decline'; end if;
 if p_approve then
   if exists(select 1 from private.game_players where game_id=g and account_id=c.requester_id) then raise exception 'This player already has a spot'; end if;
   update private.game_players set account_id=c.requester_id where id=c.participant_id and account_id is null;
   if not found then raise exception 'This spot has already been claimed'; end if;
   update private.claims set status='declined' where participant_id=c.participant_id and status='pending' and id<>c.id;
 end if;
 update private.claims set status=case when p_approve then 'approved' else 'declined' end where id=c.id;
 return private.game_json(g);
end $$;
create function public.record_score(p_game_id uuid,p_score_a integer,p_score_b integer,p_expected_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g private.games; hi integer; lo integer; begin
 select * into g from private.games where id=p_game_id and host_id=u for update;
 if not found then raise exception 'Only the host can record or correct the score'; end if;
 if p_expected_revision is distinct from g.revision then raise exception 'The score changed. Refresh the game before saving.'; end if;
 hi:=greatest(p_score_a,p_score_b);lo:=least(p_score_a,p_score_b);
 if p_score_a is null or p_score_b is null or lo<0 or hi>99 or hi<g.target or hi-lo<g.win_by or (hi>g.target and hi-lo<>g.win_by) or (g.win_by=1 and hi<>g.target) then raise exception 'Enter a completed score that matches the game format'; end if;
 update private.games set score_a=p_score_a,score_b=p_score_b,revision=revision+1,updated_at=now() where id=g.id;
 delete from private.confirmations where game_id=g.id;
 insert into private.score_changes(game_id,revision,score_a,score_b) values(g.id,g.revision+1,p_score_a,p_score_b);
 return private.game_json(g.id);
end $$;
create function public.confirm_score(p_game_id uuid,p_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g private.games; begin
 select * into g from private.games where id=p_game_id for update;
 if not found or not private.can_read_game(g.id) or g.host_id=u then raise exception 'Only a joined player can confirm the host’s score'; end if;
 if g.score_a is null or p_revision is distinct from g.revision then raise exception 'The score changed or is not recorded yet. Refresh this game.'; end if;
 insert into private.confirmations(game_id,account_id,revision) values(g.id,u,g.revision) on conflict(game_id,account_id) do update set revision=excluded.revision,confirmed_at=now();
 return private.game_json(g.id);
end $$;
create function public.list_games(p_from timestamptz default null,p_until timestamptz default null,p_search text default '',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); result jsonb; begin
 if p_offset<0 or length(p_search)>120 then raise exception 'Invalid history filter'; end if;
 select coalesce(jsonb_agg(private.game_json(id) order by starts_at desc,id),'[]'::jsonb) into result from (
   select g.id,g.starts_at from private.games g where private.can_read_game(g.id)
   and (p_from is null or g.starts_at>=p_from) and (p_until is null or g.starts_at<p_until)
   and (coalesce(btrim(p_search),'')='' or exists(select 1 from private.game_players gp left join private.profiles p on p.id=gp.account_id where gp.game_id=g.id and (gp.nickname ilike '%'||p_search||'%' or p.display_name ilike '%'||p_search||'%')))
   order by g.starts_at desc,g.id limit 30 offset p_offset
 ) q;
 return result;
end $$;

create function private.stat_json(total bigint,wins bigint) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('games',total,'wins',wins,'losses',total-wins,'win_percent',case when total>0 then round(100.0*wins/total,1) else 0 end,'loss_percent',case when total>0 then round(100.0*(total-wins)/total,1) else 0 end);
$$;
create function public.get_summary(p_peer_key text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); answer jsonb; begin
 with mine as (
  select g.*,gp.slot as my_slot,case when gp.slot<2 then g.score_a>g.score_b else g.score_b>g.score_a end won
  from private.games g join private.game_players gp on gp.game_id=g.id and gp.account_id=u where g.score_a is not null
 ), peers as (
  select m.id,m.won,((m.my_slot<2)=(gp.slot<2)) together,
  coalesce('pool:'||gp.pool_player_id::text,'user:'||gp.account_id::text,'slot:'||gp.id::text) peer_key,
  coalesce(p.display_name,'Guest - '||gp.nickname) peer_name
  from mine m join private.game_players gp on gp.game_id=m.id and gp.account_id is distinct from u
  left join private.profiles p on p.id=gp.account_id
 ) select jsonb_build_object(
  'overall',(select private.stat_json(count(*),count(*) filter(where won)) from mine),
  'with_player',(select private.stat_json(count(*),count(*) filter(where won)) from peers where peer_key=p_peer_key and together),
  'against_player',(select private.stat_json(count(*),count(*) filter(where won)) from peers where peer_key=p_peer_key and not together),
  'people',coalesce((select jsonb_agg(jsonb_build_object('key',peer_key,'name',peer_name,'games',games) order by peer_name,peer_key) from (select peer_key,min(peer_name) peer_name,count(*) games from peers group by peer_key) z),'[]'::jsonb)
 ) into answer;
 return answer;
end $$;

create function public.delete_my_account(p_confirmation text) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); begin
 if p_confirmation is distinct from 'DELETE' then raise exception 'Type DELETE to confirm'; end if;
 -- Remove identity from the shared records the person claimed, then delete their owned data.
 update private.players set nickname='Deleted player' where id in(select pool_player_id from private.game_players where account_id=u and pool_player_id is not null);
 update private.game_players set nickname='Deleted player',account_id=null where account_id=u;
 delete from auth.users where id=u;
end $$;

-- Revoke PostgreSQL's default PUBLIC function access before granting exact APIs.
revoke all on all functions in schema private from public, anon, authenticated;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['bootstrap','save_profile','add_club','add_player','save_group','create_game','get_game','get_invite_link','revoke_invite','get_invitation','request_spot','review_claim','record_score','confirm_score','list_games','get_summary','delete_my_account']) loop
   execute format('revoke all on function %s from public, anon, authenticated',f.signature);
   execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
grant execute on function public.get_invitation(text) to anon;
commit;
