-- Apply after 001 and 002. Adds date comparisons for games WITH a player.
-- The earlier opponent-period RPC remains available for the same selected range.
begin;

create function public.get_teammate_stats(
  p_peer_key text,
  p_from timestamptz default null,
  p_until timestamptz default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); answer jsonb; begin
  if p_peer_key is null or length(p_peer_key) > 100 or
     (p_from is not null and p_until is not null and p_from >= p_until) then
    raise exception 'Invalid teammate or date range';
  end if;

  select private.stat_json(count(*), count(*) filter (where won)) into answer
  from (
    select case when mine.slot < 2 then g.score_a > g.score_b else g.score_b > g.score_a end as won
    from private.game_players mine
    join private.games g on g.id = mine.game_id
    join private.game_players teammate on teammate.game_id = g.id and teammate.id <> mine.id and
      (mine.slot < 2) = (teammate.slot < 2)
    where mine.account_id = u and g.score_a is not null
      and coalesce('pool:'||teammate.pool_player_id::text,
                   'user:'||teammate.account_id::text,
                   'slot:'||teammate.id::text) = p_peer_key
      and (p_from is null or g.starts_at >= p_from)
      and (p_until is null or g.starts_at < p_until)
  ) result;
  return answer;
end $$;

revoke all on function public.get_teammate_stats(text,timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.get_teammate_stats(text,timestamptz,timestamptz) to authenticated;
commit;
