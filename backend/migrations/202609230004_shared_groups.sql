-- Shared, account-based groups. The existing player pools remain private shortcuts for entry.
begin;

-- Game invitations remain valid until the host revokes or rotates them.
alter table private.invites alter column expires_at drop not null;
alter table private.invites alter column expires_at drop default;
update private.invites set expires_at=null;

create or replace function public.get_invite_link(p_game_id uuid,p_rotate boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 if not exists(select 1 from private.games where id=p_game_id and host_id=auth.uid()) then raise exception 'Only the host can share this game'; end if;
 if p_rotate then update private.invites set token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),expires_at=null,revoked=false where game_id=p_game_id; end if;
 return (select jsonb_build_object('token',token,'expires_at',expires_at,'revoked',revoked) from private.invites where game_id=p_game_id);
end $$;

create or replace function private.invited_game(t text,for_claim boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare i private.invites; begin
 if t is null or t !~ '^[0-9a-f]{64}$' then raise exception 'This invitation is unavailable'; end if;
 select * into i from private.invites where token=t;
 if not found then raise exception 'This invitation is unavailable'; end if;
 if i.revoked then
   if for_claim or not private.can_read_game(i.game_id) then raise exception 'This invitation was closed. Ask the host for a new link.'; end if;
 end if;
 return i.game_id;
end $$;

create table private.shared_groups (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references private.profiles(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 60),
 eligibility text not null default 'one_each' check(eligibility in ('one_each','all_players')),
 created_at timestamptz not null default now()
);
create table private.shared_group_members (
 group_id uuid not null references private.shared_groups(id) on delete cascade,
 account_id uuid not null references private.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(group_id,account_id)
);
create index shared_group_members_account on private.shared_group_members(account_id,group_id);
create table private.shared_group_invites (
 group_id uuid primary key references private.shared_groups(id) on delete cascade,
 token text not null unique default(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','')),
 revoked boolean not null default false
);
do $$ declare t text; begin
 foreach t in array array['shared_groups','shared_group_members','shared_group_invites'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public, anon, authenticated',t);
 end loop;
end $$;

create function public.list_shared_groups() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); begin
 return coalesce((select jsonb_agg(jsonb_build_object(
    'id',g.id,'name',g.name,'eligibility',g.eligibility,'owner_id',g.owner_id,
    'members',(select jsonb_agg(jsonb_build_object('id',m.account_id,'name',p.display_name) order by p.display_name,m.account_id)
       from private.shared_group_members m join private.profiles p on p.id=m.account_id where m.group_id=g.id)
  ) order by g.name,g.id)
  from private.shared_groups g join private.shared_group_members mine on mine.group_id=g.id and mine.account_id=u),'[]'::jsonb);
end $$;

create function public.create_shared_group(p_name text,p_eligibility text default 'one_each') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g uuid; begin
 if p_name is null or length(btrim(p_name)) not between 1 and 60 then raise exception 'Enter a group name (1–60 characters)'; end if;
 if p_eligibility is null or p_eligibility not in('one_each','all_players') then raise exception 'Choose a group game rule'; end if;
 insert into private.shared_groups(owner_id,name,eligibility) values(u,btrim(p_name),p_eligibility) returning id into g;
 insert into private.shared_group_members(group_id,account_id) values(g,u);
 insert into private.shared_group_invites(group_id) values(g);
 return public.list_shared_groups();
end $$;

create function public.set_shared_group_rule(p_group_id uuid,p_eligibility text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 if p_eligibility is null or p_eligibility not in('one_each','all_players') then raise exception 'Choose a group game rule'; end if;
 update private.shared_groups set eligibility=p_eligibility where id=p_group_id and owner_id=auth.uid();
 if not found then raise exception 'Only the group creator can change its rule'; end if;
 return public.list_shared_groups();
end $$;

create function public.get_shared_group_invite(p_group_id uuid,p_rotate boolean default false) returns text language plpgsql security definer set search_path='' as $$
declare t text; begin
 perform private.require_user();
 if not exists(select 1 from private.shared_group_members where group_id=p_group_id and account_id=auth.uid()) then raise exception 'Group unavailable'; end if;
 if p_rotate then update private.shared_group_invites set token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),revoked=false where group_id=p_group_id; end if;
 select token into t from private.shared_group_invites where group_id=p_group_id and not revoked;
 if t is null then raise exception 'Group invitation is closed'; end if;
 return t;
end $$;

create function public.join_shared_group(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); g uuid; begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'Group invitation unavailable'; end if;
 select group_id into g from private.shared_group_invites where token=p_token and not revoked;
 if g is null then raise exception 'Group invitation unavailable'; end if;
 insert into private.shared_group_members(group_id,account_id) values(g,u) on conflict do nothing;
 return public.list_shared_groups();
end $$;

-- A group game is calculated from current claimed identities and current group membership.
-- Guests cannot be counted from nicknames: matching a name is not proof of identity.
create function public.get_shared_group_board(p_group_id uuid,p_view text default 'players',p_from timestamptz default null,p_until timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); rule text; result jsonb; begin
 select g.eligibility into rule from private.shared_groups g join private.shared_group_members m on m.group_id=g.id and m.account_id=u where g.id=p_group_id;
 if rule is null then raise exception 'Group unavailable'; end if;
 if p_view not in ('players','partners','singles') or p_view is null then raise exception 'Unknown leaderboard view'; end if;
 if p_from is not null and p_until is not null and p_until<=p_from then raise exception 'Invalid date range'; end if;
 with qualified as (
   select g.id,g.starts_at,g.score_a,g.score_b,g.game_type,
     array_agg(gp.account_id order by gp.slot) ids,
     array_agg(gp.account_id in (select m.account_id from private.shared_group_members m where m.group_id=p_group_id) order by gp.slot) belongs
   from private.games g join private.game_players gp on gp.game_id=g.id
   where g.score_a is not null and g.score_b is not null
    and (p_from is null or g.starts_at>=p_from) and (p_until is null or g.starts_at<p_until)
   group by g.id
 ), eligible as (
   select * from qualified where
    (game_type='doubles' and array_length(ids,1)=4 and
      (rule='all_players' and belongs=array[true,true,true,true] or
       rule='one_each' and (belongs[1] or belongs[2]) and (belongs[3] or belongs[4])))
    or (game_type='singles' and array_length(ids,1)=2 and belongs=array[true,true])
 ), results as (
   select e.id game_id,e.starts_at,e.game_type,gp.account_id,gp.slot,gp.slot<2 team_a,
     case when gp.slot<2 then e.score_a>e.score_b else e.score_b>e.score_a end won,
     partner.account_id partner_id
   from eligible e join private.game_players gp on gp.game_id=e.id
   join private.shared_group_members member on member.group_id=p_group_id and member.account_id=gp.account_id
   left join private.game_players partner on partner.game_id=e.id and partner.slot=case gp.slot when 0 then 1 when 1 then 0 when 2 then 3 else 2 end
 ), leaderboard as (
   select r.account_id,case when p_view='partners' then r.partner_id end partner_id,
    count(*) games,count(*) filter(where r.won) wins
   from results r where (p_view='players' and r.game_type='doubles')
     or (p_view='partners' and r.game_type='doubles' and r.partner_id is not null)
     or (p_view='singles' and r.game_type='singles')
   group by r.account_id,case when p_view='partners' then r.partner_id end
 )
 select jsonb_build_object(
   'games',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'starts_at',e.starts_at,'game_type',e.game_type,'score_a',e.score_a,'score_b',e.score_b) order by e.starts_at desc,e.id) from eligible e where e.game_type=case when p_view='singles' then 'singles' else 'doubles' end),'[]'::jsonb),
   'leaders',coalesce((select jsonb_agg(jsonb_build_object('account_id',l.account_id,'name',p.display_name,'partner_id',l.partner_id,'partner_name',coalesce(pp.display_name,'Guest partner'),
     'games',l.games,'wins',l.wins,'losses',l.games-l.wins,'win_percent',round(100.0*l.wins/l.games,1)) order by l.wins desc,l.games desc,p.display_name,l.account_id)
     from leaderboard l join private.profiles p on p.id=l.account_id left join private.profiles pp on pp.id=l.partner_id),'[]'::jsonb)
 ) into result;
 return result;
end $$;

revoke all on function public.get_invite_link(uuid,boolean),private.invited_game(text,boolean) from public,anon,authenticated;
revoke all on function public.list_shared_groups(),public.create_shared_group(text,text),public.set_shared_group_rule(uuid,text),public.get_shared_group_invite(uuid,boolean),public.join_shared_group(text),public.get_shared_group_board(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.get_invite_link(uuid,boolean),public.list_shared_groups(),public.create_shared_group(text,text),public.set_shared_group_rule(uuid,text),public.get_shared_group_invite(uuid,boolean),public.join_shared_group(text),public.get_shared_group_board(uuid,text,timestamptz,timestamptz) to authenticated;
commit;
