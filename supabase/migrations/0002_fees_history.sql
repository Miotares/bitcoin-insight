-- Bitcoin Insight — recommended-fee history
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Purpose: mempool.space has NO historical recommended-fees endpoint
-- (/api/v1/fees/recommended/* → 404). Every other history chart in the app
-- (price, hashrate, mempool tx count, lightning, difficulty) is served natively
-- by mempool.space, so ONLY fees need to be accumulated server-side.
--
-- The backend already fetches the current fees every minute into
-- network_stats.payload->'fees'. We just snapshot that value every 10 minutes
-- into a slim time-series table — no extra mempool.space call.
-- Footprint: 144 rows/day ≈ 0.5 MB/year (free tier is 500 MB).

-- Table ---------------------------------------------------------------------
create table if not exists public.fees_history (
    id          bigint generated always as identity primary key,
    recorded_at timestamptz not null default now(),
    fast        integer not null,   -- fastestFee  (sat/vB)
    half_hour   integer not null,   -- halfHourFee (sat/vB)
    hour        integer not null    -- hourFee     (sat/vB)
);

create index if not exists fees_history_recorded_at_idx
    on public.fees_history (recorded_at desc);

-- Read-only RLS, same pattern as public.network_stats -----------------------
alter table public.fees_history enable row level security;

drop policy if exists fees_history_read on public.fees_history;
create policy fees_history_read
    on public.fees_history
    for select
    to anon, authenticated
    using (true);

grant select on public.fees_history to anon, authenticated;

-- Snapshot function ---------------------------------------------------------
-- Copies the already-fetched current fees into the history table.
-- SECURITY DEFINER so only the scheduler path writes; guards against null fees.
create or replace function public.snapshot_fees()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_fees jsonb;
begin
    select payload->'fees' into v_fees
    from public.network_stats
    where id = 1;

    if v_fees is null
       or v_fees->>'fast' is null
       or v_fees->>'halfHour' is null
       or v_fees->>'hour' is null then
        return;
    end if;

    insert into public.fees_history (recorded_at, fast, half_hour, hour)
    values (
        now(),
        (v_fees->>'fast')::integer,
        (v_fees->>'halfHour')::integer,
        (v_fees->>'hour')::integer
    );
end;
$$;

revoke execute on function public.snapshot_fees() from anon, authenticated, public;

-- Schedule (every 10 minutes) ----------------------------------------------
select cron.schedule('snapshot-fees', '*/10 * * * *', $$select public.snapshot_fees();$$);

-- Seed one row immediately.
select public.snapshot_fees();

-- Widget/app read contract:
--   GET https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/fees_history
--       ?select=recorded_at,fast,half_hour,hour
--       &recorded_at=gte.<iso8601>
--       &order=recorded_at.asc
--   header apikey: <publishable key>
