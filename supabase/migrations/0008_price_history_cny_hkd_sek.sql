-- Bitcoin Insight — add CNY/HKD/SEK to public.price_history
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- CNY/HKD/SEK were offered in the app's currency picker but had NO column here
-- (only the 7 mempool currencies + the 9 Tier-1 additions did). Result: the price
-- detail CHART for those three was empty (mempool's historical-price returns an
-- empty body for any currency outside its 7, so the chart relies entirely on this
-- table), the live-price FX derivation (latestFXRatio) returned nil, and the
-- sparkline's derived fallback failed — all three leaned on the flaky CoinGecko.
--
-- All three ARE in the ECB EUR-base reference rates, so they derive exactly like
-- the other 16: price_CUR = price_USD * ecb[CUR] / ecb[USD]. The full historical
-- backfill (2011-09-01 -> present) is re-run via the `backfill-price-history` Edge
-- Function with its CURS array extended to include CNY/HKD/SEK. This file adds the
-- columns and extends the daily top-up append_price_history_recent().

alter table public.price_history add column if not exists cny double precision;
alter table public.price_history add column if not exists hkd double precision;
alter table public.price_history add column if not exists sek double precision;

-- Daily top-up now fills the 7 originals + 9 Tier-1 + CNY/HKD/SEK (19 total).
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

    begin
        select (extensions.http_get('https://www.bitstamp.net/api/v2/ohlc/btcusd/?step=86400&limit=5')).content::jsonb
          into v_bs;
    exception when others then return; end;

    begin
        select (extensions.http_get('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml')).content
          into v_ecb;
    exception when others then return; end;

    -- Quote-agnostic: the daily XML uses single quotes, the hist XML double.
    select jsonb_object_agg(arr[1], to_jsonb(arr[2]::double precision))
      into v_rates
      from (select regexp_matches(v_ecb, 'currency=["'']([A-Z]{3})["'']\s+rate=["'']([0-9.]+)["'']', 'g') as arr) s;

    v_usd_per_eur := (v_rates->>'USD')::double precision;
    if v_usd_per_eur is null or v_bs is null then return; end if;

    for c in
        select to_timestamp((e->>'timestamp')::bigint)::date as day,
               (e->>'close')::double precision as close
        from jsonb_array_elements(v_bs->'data'->'ohlc') as e
    loop
        if c.close is null or c.close <= 0 then continue; end if;
        insert into public.price_history
            (day, usd, eur, gbp, chf, cad, aud, jpy,
             brl, inr, mxn, krw, thb, idr, "try", czk, pln,
             cny, hkd, sek, source)
        values (
            c.day, c.close,
            c.close / v_usd_per_eur,
            c.close * (v_rates->>'GBP')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CHF')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CAD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'AUD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'JPY')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'BRL')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'INR')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'MXN')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'KRW')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'THB')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'IDR')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'TRY')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CZK')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'PLN')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'CNY')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'HKD')::double precision / v_usd_per_eur,
            c.close * (v_rates->>'SEK')::double precision / v_usd_per_eur,
            'bitstamp+ecb'
        )
        on conflict (day) do update set
            usd=excluded.usd, eur=excluded.eur, gbp=excluded.gbp, chf=excluded.chf,
            cad=excluded.cad, aud=excluded.aud, jpy=excluded.jpy,
            brl=excluded.brl, inr=excluded.inr, mxn=excluded.mxn, krw=excluded.krw,
            thb=excluded.thb, idr=excluded.idr, "try"=excluded."try",
            czk=excluded.czk, pln=excluded.pln,
            cny=excluded.cny, hkd=excluded.hkd, sek=excluded.sek,
            source=excluded.source;
    end loop;
end;
$$;

revoke execute on function public.append_price_history_recent() from anon, authenticated, public;

-- One-time backfill of the new columns: extend the Edge Function CURS to include
-- CNY/HKD/SEK, redeploy, then invoke once (idempotent upsert on `day`):
--   curl -s -X POST -H "apikey: <publishable>" \
--     https://hyyagnnsjbpsehriyafn.supabase.co/functions/v1/backfill-price-history
-- Done 2026-06-24: 5411 rows, 2011-09-01 -> present, all 19 currency columns full.
