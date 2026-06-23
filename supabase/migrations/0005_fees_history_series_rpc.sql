-- Bitcoin Insight — bounded downsampling for the fees chart
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Why: PostgREST caps a plain table response at 1000 rows, so reading
-- public.fees_history directly (it grows 144 rows/day) silently truncates the
-- 1M / All ranges once enough data accumulates — the chart would show only the
-- newest ~7 days. This RPC buckets the requested window into <=`buckets` equal
-- TIME buckets and returns the latest row per bucket, so ANY range comes back in
-- ONE request at a bounded, screen-appropriate size.
--
-- SECURITY INVOKER: runs as the caller (anon already has SELECT on fees_history),
-- so no privilege escalation. Exposed to anon/authenticated for the app to call.

create or replace function public.fees_history_series(
    since   timestamptz default (now() - interval '30 days'),
    buckets int         default 600
)
returns table(recorded_at timestamptz, fast int, half_hour int, hour int)
language sql
stable
security invoker
set search_path = public
as $$
    with params as (
        select greatest(10, least(coalesce(buckets, 600), 1000)) as n
    ),
    src as (
        select fh.recorded_at, fh.fast, fh.half_hour, fh.hour
        from public.fees_history fh
        where fh.recorded_at >= since
    ),
    bounds as (
        select extract(epoch from min(src.recorded_at)) as lo,
               extract(epoch from max(src.recorded_at)) as hi
        from src
    ),
    bucketed as (
        select src.*,
            case when bounds.hi > bounds.lo
                 then width_bucket(extract(epoch from src.recorded_at),
                                   bounds.lo, bounds.hi, (select n from params))
                 else 1 end as bk
        from src, bounds
    )
    select distinct on (bk) bucketed.recorded_at, bucketed.fast, bucketed.half_hour, bucketed.hour
    from bucketed
    order by bk, bucketed.recorded_at desc;
$$;

grant execute on function public.fees_history_series(timestamptz, int) to anon, authenticated;

-- App read contract:
--   POST https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/rpc/fees_history_series
--        body {"since": "<iso8601>", "buckets": 600}
--        header apikey: <publishable key>
