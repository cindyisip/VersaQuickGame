-- Apply after 202609230001_initial.sql. Adds a narrow opponent-only period query.
begin;

create function public.get_opponent_stats(
  p_peer_key text,
  p_from timestamptz default null,
  p_until timestamptz default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); answer jsonb; begin
  if p_peer_key is null or length(p_peer_key) > 100 or
     (p_from is not null and p_until is not null and p_from >= p_until) then
    raise exception 'Invalid opponent or date range';
  end if;

  select private.stat_json(count(*), count(*) filter (where won)) into answer
  from (
    select case when mine.slot < 2 then g.score_a > g.score_b else g.score_b > g.score_a end as won
    from private.game_players mine
    join private.games g on g.id = mine.game_id
    join private.game_players opponent on opponent.game_id = g.id and
      (mine.slot < 2) <> (opponent.slot < 2)
    where mine.account_id = u and g.score_a is not null
      and coalesce('pool:'||opponent.pool_player_id::text,
                   'user:'||opponent.account_id::text,
                   'slot:'||opponent.id::text) = p_peer_key
      and (p_from is null or g.starts_at >= p_from)
      and (p_until is null or g.starts_at < p_until)
  ) result;
  return answer;
end $$;

revoke all on function public.get_opponent_stats(text,timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.get_opponent_stats(text,timestamptz,timestamptz) to authenticated;
commit;
