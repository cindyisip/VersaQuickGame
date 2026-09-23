-- Singles games have the host in slot 0 and the opponent in slot 2.
begin;
alter table private.games add column game_type text not null default 'doubles' check(game_type in ('singles','doubles'));
create or replace function private.game_json(g uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
   'id',x.id,'game_type',x.game_type,'host_id',x.host_id,'host_name',p.display_name,'place',x.place,'court',x.court,
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

create or replace function public.create_game(p_place text,p_court text,p_starts_at timestamptz,p_target integer,p_scoring text,p_win_by integer,p_players jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if jsonb_typeof(p_players) is distinct from 'array' or jsonb_array_length(p_players) not in(1,3) then raise exception 'Add an opponent or three other players'; end if;
 insert into private.games(id,host_id,place,court,starts_at,target,scoring,win_by,game_type) values(p_request_id,u,btrim(p_place),btrim(coalesce(p_court,'')),p_starts_at,p_target,p_scoring,p_win_by,case when jsonb_array_length(p_players)=1 then 'singles' else 'doubles' end) returning id into g;
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
   insert into private.game_players(game_id,slot,pool_player_id,nickname) values(g,case when jsonb_array_length(p_players)=1 then 2 else s end,pid,n);
   s:=s+1;
 end loop;
 insert into private.invites(game_id) values(g);
 return private.game_json(g);
end $$;
commit;
