-- Bitcoin Insight — daily top-up for public.price_history
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Appends the last few days' BTC price in all 7 currencies so the dense daily
-- series stays current between full backfills. Light: small Bitstamp + ECB-DAILY
-- fetches via the http extension (NOT the 8 MB hist file), same pattern as
-- refresh_network_stats / snapshot_fees. The one-time deep backfill is the
-- `backfill-price-history` Edge Function (see supabase/functions/); this just keeps
-- the recent end fresh, so the app's chart-merge seam stays close to today.

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create or replace function public.append_price_history_recent()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_bs    jsonb;
    v_ecb   text;
    v_rates jsonb;
    v_usd_per_eur double precision;
    c record;
begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '8000');

    -- Bitstamp: last 5 daily BTC/USD candles.
    begin
        select (extensions.http_get('https://www.bitstamp.net/api/v2/ohlc/btcusd/?step=86400&limit=5')).content::jsonb
          into v_bs;
    exception when others then return; end;

    -- ECB: latest daily reference rates (regex the currency/rate pairs out of the XML).
    begin
        select (extensions.http_get('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml')).content
          into v_ecb;
    exception when others then return; end;

    select jsonb_object_agg(arr[1], to_jsonb(arr[2]::double precision))
      into v_rates
      from (select regexp_matches(v_ecb, 'currency="([A-Z]{3})"\s+rate="([0-9.]+)"', 'g') as arr) s;

    v_usd_per_eur := (v_rates->>'USD')::double precision;
    if v_usd_per_eur is null or v_bs is null then return; end if;

    for c in
        select to_timestamp((e->>'timestamp')::bigint)::date as day,
               (e->>'close')::double precision as close
        from jsonb_array_elements(v_bs->'data'->'ohlc') as e
    loop
        if c.close is null or c.close <= 0 then continue; end if;
        insert into public.price_history (day, usd, eur, gbp, chf, cad, aud, jpy, source)
        values (
            c.day, c.close,
            c.close / v_usd_per_eur,
            c.close * (v_rates->>'GBP')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CHF')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CAD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'AUD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'JPY')::double precision / v_usd_per_eur,
            'bitstamp+ecb'
        )
        on conflict (day) do update set
            usd=excluded.usd, eur=excluded.eur, gbp=excluded.gbp, chf=excluded.chf,
            cad=excluded.cad, aud=excluded.aud, jpy=excluded.jpy, source=excluded.source;
    end loop;
end;
$$;

-- Only the scheduler (postgres) may run the writer — not anon/authenticated.
revoke execute on function public.append_price_history_recent() from anon, authenticated, public;

-- Schedule daily at 01:15 (re-runnable: drop any existing job of the same name).
do $$ begin perform cron.unschedule('append-price-history'); exception when others then null; end $$;
select cron.schedule('append-price-history', '15 1 * * *', 'select public.append_price_history_recent();');
