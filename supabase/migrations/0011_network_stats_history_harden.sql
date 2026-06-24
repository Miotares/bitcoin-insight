-- The snapshot writer must NOT be a public endpoint. Only pg_cron (postgres) calls it.
revoke execute on function public.snapshot_network_stats() from public, anon, authenticated;

-- Match the established fees_history pattern: the read RPC runs as the caller
-- (SECURITY INVOKER) and a read-only policy lets anon/authenticated see the history.
-- This also clears the SECURITY DEFINER + rls-no-policy advisor notices.
alter function public.network_stats_sparklines() security invoker;

create policy "network_stats_history read"
    on public.network_stats_history
    for select
    to anon, authenticated
    using (true);

-- NOTE: a one-time hashrate backfill was also run live (best-effort, via the http
-- extension) so the 30-day line is populated immediately:
--   insert into public.network_stats_history (recorded_at, hashrate)
--   select to_timestamp((e->>'timestamp')::bigint), (e->>'avgHashrate')::double precision
--   from jsonb_array_elements(
--     (extensions.http_get('https://mempool.space/api/v1/mining/hashrate/1m')).content::jsonb -> 'hashrates'
--   ) e
--   where (e->>'timestamp')::bigint >= extract(epoch from now() - interval '32 days');
