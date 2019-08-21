begin;

create table public.cats (
    cat_id           serial   not null,
    cat_name         text     not null,
    cat_age_in_month smallint not null check (cat_age_in_month > 0),
    is_kitten        boolean  not null,
    constraint cats_pkey primary key (cat_id),
    constraint cats_name_ukey unique (cat_name),
    constraint cats_is_kitten_ck check (
        is_kitten and cat_age_in_month <= 2
        or not is_kitten and cat_age_in_month > 2
    )
);

select pgmock.mock($$
    {
        "oid": "${'public.cats'::regclass}",
        "constraints": ["cats_pkey", "cats_is_kitten_ck", "cats_name_ukey"],
        "not_nulls": ["cat_name", "cat_age_in_month"]
    }
$$);

select pg_temp.setup();

-- mock for primary key
select exists(
    select from pg_constraint c
    where c.conrelid = 'pg_temp.cats'::regclass
        and c.contype = 'p'
);

-- mock for check constraint
select exists(
    select from pg_constraint c
    where c.conrelid = 'pg_temp.cats'::regclass
        and c.contype = 'c'
        and c.conname = 'cats_is_kitten_ck'
);

-- mock for qunique constraint
select exists(
    select from pg_constraint c
    where c.conrelid = 'pg_temp.cats'::regclass
        and c.contype = 'u'
        and c.conname = 'cats_name_ukey'
);

-- is_kitten column without not null constraint
select a.attnotnull
from pg_attribute a
where a.attrelid = 'pg_temp.cats'::regclass
    and a.attname = 'is_kitten';

-- cat_name column with not null constraint
select a.attnotnull
from pg_attribute a
where a.attrelid = 'pg_temp.cats'::regclass
    and a.attname = 'cat_name';

-- cat_age_in_month column with not null constraint
select a.attnotnull
from pg_attribute a
where a.attrelid = 'pg_temp.cats'::regclass
    and a.attname = 'cat_age_in_month';

select pg_temp.teardown();

rollback;