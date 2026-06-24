-- Bitcoin Insight — serve ALL 19 offered currencies in the widget feed
-- Applied to Supabase project `bitcoin-insight` (hyyagnnsjbpsehriyafn) via MCP.
-- This file is the canonical reference; re-runnable.
--
-- Bug: refresh_network_stats() only emitted the 7 mempool currencies into
-- network_stats.payload.prices. A widget for any of the other 12 offered
-- currencies (CNY/HKD/SEK/BRL/INR/MXN/KRW/THB/IDR/TRY/CZK/PLN) then fell back to
-- USD (NetworkSnapshot.price(for:)), so e.g. a "BTC/THB" widget actually showed
-- the USD number. Fix: derive the 12 from the live USD price x today's FX ratio
-- (price_history.cur / price_history.usd, latest daily row) — the exact method the
-- app uses client-side. Every other payload field is preserved verbatim.

create or replace function public.refresh_network_stats()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
    v_prices    jsonb;
    v_height    bigint;
    v_fees      jsonb;
    v_mempool   jsonb;
    v_mining    jsonb;
    v_adj       jsonb;
    v_ln        jsonb;
    v_existing  jsonb;
    v_payload   jsonb;
    v_price_obj jsonb;
    v_derived   jsonb;
    v_fx        jsonb;
    v_usd       numeric;
    v_usd_fx    numeric;
begin
    select payload into v_existing from public.network_stats where id = 1;

    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '4000');

    begin select (extensions.http_get('https://mempool.space/api/v1/prices')).content::jsonb into v_prices;
    exception when others then v_prices := null; end;

    begin select trim(both from (extensions.http_get('https://mempool.space/api/blocks/tip/height')).content)::bigint into v_height;
    exception when others then v_height := null; end;

    begin select (extensions.http_get('https://mempool.space/api/v1/fees/recommended')).content::jsonb into v_fees;
    exception when others then v_fees := null; end;

    begin select (extensions.http_get('https://mempool.space/api/mempool')).content::jsonb into v_mempool;
    exception when others then v_mempool := null; end;

    begin select (extensions.http_get('https://mempool.space/api/v1/mining/hashrate/3d')).content::jsonb into v_mining;
    exception when others then v_mining := null; end;

    begin select (extensions.http_get('https://mempool.space/api/v1/difficulty-adjustment')).content::jsonb into v_adj;
    exception when others then v_adj := null; end;

    begin select (extensions.http_get('https://mempool.space/api/v1/lightning/statistics/latest')).content::jsonb into v_ln;
    exception when others then v_ln := null; end;

    -- prices: 7 live from mempool + 12 derived from live USD x today's FX ratio.
    if v_prices is not null and (v_prices ? 'USD') then
        v_price_obj := jsonb_build_object(
            'USD', v_prices->'USD', 'EUR', v_prices->'EUR', 'GBP', v_prices->'GBP',
            'CAD', v_prices->'CAD', 'CHF', v_prices->'CHF', 'AUD', v_prices->'AUD',
            'JPY', v_prices->'JPY'
        );
        v_usd := nullif(v_prices->>'USD','')::numeric;
        select to_jsonb(ph) into v_fx from public.price_history ph order by day desc limit 1;
        v_usd_fx := nullif(v_fx->>'usd','')::numeric;
        if v_usd is not null and v_usd > 0 and v_usd_fx is not null and v_usd_fx > 0 then
            select coalesce(jsonb_object_agg(code,
                       to_jsonb(round(v_usd * (v_fx->>lower(code))::numeric / v_usd_fx))), '{}'::jsonb)
              into v_derived
              from unnest(array['CNY','HKD','SEK','BRL','INR','MXN','KRW','THB','IDR','TRY','CZK','PLN']) code
             where v_fx->>lower(code) is not null;
            v_price_obj := v_price_obj || coalesce(v_derived, '{}'::jsonb);
        end if;
    else
        v_price_obj := v_existing->'prices';
    end if;

    v_payload := jsonb_build_object(
        'prices', coalesce(v_price_obj, v_existing->'prices'),
        'blockHeight', coalesce(to_jsonb(v_height), v_existing->'blockHeight'),
        'fees', coalesce(
            case when v_fees is not null then jsonb_build_object(
                'fast', v_fees->'fastestFee', 'halfHour', v_fees->'halfHourFee', 'hour', v_fees->'hourFee'
            ) end, v_existing->'fees'),
        'mempoolCount', coalesce(v_mempool->'count', v_existing->'mempoolCount'),
        'hashrate', coalesce(v_mining->'currentHashrate', v_existing->'hashrate'),
        'difficulty', coalesce(v_mining->'currentDifficulty', v_existing->'difficulty'),
        'difficultyAdjustment', coalesce(
            case when v_adj is not null then jsonb_build_object(
                'progressPercent', v_adj->'progressPercent',
                'remainingBlocks', v_adj->'remainingBlocks',
                'estimatedRetargetPercentage', v_adj->'estimatedRetargetPercentage'
            ) end, v_existing->'difficultyAdjustment'),
        'lightning', coalesce(
            case when (v_ln->'latest') is not null then jsonb_build_object(
                'channels', v_ln->'latest'->'channel_count',
                'nodes', v_ln->'latest'->'node_count',
                'capacity', v_ln->'latest'->'total_capacity'
            ) end, v_existing->'lightning')
    );

    insert into public.network_stats (id, payload, updated_at)
    values (1, v_payload, now())
    on conflict (id) do update
        set payload = excluded.payload, updated_at = excluded.updated_at;
end;
$function$;

revoke execute on function public.refresh_network_stats() from anon, authenticated, public;

-- Seed immediately so the new currencies appear without waiting for the cron tick.
select public.refresh_network_stats();

-- Widget read contract (unchanged endpoint, now 19 currency keys):
--   GET https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/network_stats?select=payload,updated_at&id=eq.1
--   payload.prices = {USD,EUR,GBP,CAD,CHF,AUD,JPY, CNY,HKD,SEK,BRL,INR,MXN,KRW,THB,IDR,TRY,CZK,PLN}
