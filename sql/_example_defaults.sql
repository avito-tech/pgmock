begin;

create table public.cats (
    cat_id     serial                   not null primary key,
    cat_name   text                     not null default 'Kot',
    created_at timestamp with time zone not null default now()
);

select pgmock.mock($$
    {
        "oid": "${'public.cats'::regclass}",
        "defaults": ["cat_id", "cat_name", "created_at"]
    }
$$);

-- default value for column cat_id (sequence)
select exists(
    select from pg_attrdef ad
        join pg_attribute a on (a.attrelid = ad.adrelid and a.attnum = ad.adnum)
    where a.attrelid = 'pg_temp.cats'::regclass
        and a.attname = 'cat_id'
);

-- default value for column cat_name (literal)
select exists(
    select from pg_attrdef ad
        join pg_attribute a on (a.attrelid = ad.adrelid and a.attnum = ad.adnum)
    where a.attrelid = 'pg_temp.cats'::regclass
        and a.attname = 'cat_name'
);

-- default value for column created_at (function)
select exists(
    select from pg_attrdef ad
        join pg_attribute a on (a.attrelid = ad.adrelid and a.attnum = ad.adnum)
    where a.attrelid = 'pg_temp.cats'::regclass
        and a.attname = 'created_at'
);

rollback;