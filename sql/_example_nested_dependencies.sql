begin;

create table public.cats (
    cat_id   serial not null,
    cat_name text   not null unique,
    constraint cats_pkey primary key (cat_id)
);

create function public.add_cat(
    name text
) returns integer volatile language sql as
$func$
    insert into public.cats (cat_name) values (name) returning cat_id;
$func$;

create function public.get_cat(
    name text
) returns integer volatile language sql as
$func$
    select c.cat_id
    from public.cats c
    where c.cat_name = name;
$func$;

create function public.set_cat(
    name text
) returns integer volatile language plpgsql as
$func$
declare
    cat_id integer;
begin
    cat_id := public.get_cat(name);

    if cat_id is null then
        cat_id := public.add_cat(name);
    end if;

    return cat_id;
end;
$func$;

insert into public.cats (cat_name) values ('Barsik'), ('Snezhok'), ('Muska');

select pgmock.mock($$
    {
        "oid": "${'public.set_cat'::regproc}",
        "dependencies": [
            {
                "oid": "${'public.add_cat'::regproc}",
                "dependencies": {
                    "oid": "${'public.cats'::regclass}",
                    "mock_name": "cats_mock",
                    "constraints": ["cats_pkey"],
                    "defaults": ["cat_id"]
                }
            },
            {
                "oid": "${'public.get_cat'::regproc}",
                "dependencies": "${'public.cats'::regclass}"
            }
        ]
    }
$$);

select pg_temp.setup();

-- resultset should be empty
select * from pg_temp.cats_mock;

-- value should be added to substituted context
select pg_temp.add_cat('Rizhik') is not null;

select cat_id, cat_name from pg_temp.cats_mock;

-- value shoud be retrieved from substituted context
select pg_temp.get_cat('Rizhik') = c.cat_id from pg_temp.cats_mock c;

-- set for existing record
select pg_temp.set_cat('Rizhik') = pg_temp.get_cat('Rizhik');

-- set for nonexisting record
select pg_temp.get_cat('Snezhok') is null;

select pg_temp.set_cat('Snezhok') is not null;

select pg_temp.teardown();

rollback;