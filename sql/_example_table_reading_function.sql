begin;

create table public.cats (
    cat_id             serial   primary key,
    cat_name           text     not null,
    cat_age_in_months  smallint not null
);

insert into public.cats (cat_name, cat_age_in_months)
values
    ('Barsik', 12), ('Murzik', 10), ('Luska', 23),
    ('Rijik', 3), ('Snejok', 38), ('Barsik', 8)
;

create function public.get_cat_stats(
    out oldest_cat_name   text,
    out youngest_cat_name text,
    out min_age_in_months smallint,
    out avg_age_in_months smallint,
    out max_age_in_months smallint
) returns record language plpgsql as
$func$
begin
    select
        first_value(c.cat_name)
            over (order by c.cat_age_in_months desc) as oldest_cat_name,
        first_value(c.cat_name)
            over (order by c.cat_age_in_months asc)  as youngest_cat_name,
        min(c.cat_age_in_months) over ()             as min_age_in_months,
        round(avg(c.cat_age_in_months) over ())      as avg_age_in_months,
        max(c.cat_age_in_months) over ()             as max_age_in_months
    into
        oldest_cat_name,
        youngest_cat_name,
        min_age_in_months,
        avg_age_in_months,
        max_age_in_months
    from
        public.cats c
    limit 1;

    return;
end;
$func$;

select pgmock.mock($$
    {
        "oid": "${'public.get_cat_stats'::regproc}",
        "dependencies": "${'public.cats'::regclass}"
    }
$$);

select pg_temp.setup();

-- identical structure (resultset should be empty)
with w_original as (
    select a.attname, a.attnum, a.atttypid
    from pg_attribute a
    where a.attrelid = 'public.cats'::regclass
        and not a.attisdropped
        and a.attnum > 0
), w_mock as (
    select a.attname, a.attnum, a.atttypid
    from pg_attribute a
    where a.attrelid = 'pg_temp.cats'::regclass
        and not a.attisdropped
        and a.attnum > 0
)
(select * from w_original except all select * from w_mock)
union all
(select * from w_mock except all select * from w_original);

-- table mock is empty
select * from pg_temp.cats;

-- function mock exists
select exists(
    select from pg_proc p where p.oid = 'pg_temp.get_cat_stats'::regproc
);

-- function mock doesn't use original context (all nulls)
select * from pg_temp.get_cat_stats();

-- function mock uses substituted context
insert into pg_temp.cats (cat_name, cat_age_in_months)
values ('Barsik', 12), ('Murzik', 8);

select * from pg_temp.get_cat_stats();

select pg_temp.teardown();

-- context is clean after pg_temp.teardown() call
select * from pg_temp.cats;

rollback;