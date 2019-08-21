begin;

create table public.cats (
    cat_id   serial not null primary key,
    cat_name text   not null
);

create table public.cat_toys (
    toy_id   serial  not null primary key,
    cat_id   integer not null references public.cats (cat_id)
                              deferrable initially deferred,
    toy_name text    not null
);

create function public.cats_aid() returns trigger language plpgsql as
$func$
begin
    if TG_OP = 'INSERT' then
        insert into public.cat_toys (cat_id, toy_name)
        values (NEW.cat_id, format('Toy for %s', NEW.cat_name));
    elsif TG_OP = 'DELETE' then
        delete from public.cat_toys ct where ct.cat_id = OLD.cat_id;
    end if;

    return null;
end;
$func$;

create trigger cats_aid_trg after insert or delete on public.cats
    for each row execute procedure public.cats_aid();

select pgmock.mock($$
    {
        "oid": "${'public.cats'::regclass}",
        "defaults": ["cat_id"],
        "triggers": [{
            "name": "cats_aid_trg",
            "procedure": {
                "oid": "${'public.cats_aid'::regproc}",
                "dependencies": "${'public.cat_toys'::regclass}"
            }
        }]
    }
$$);

select pg_temp.setup();

-- mock for table cats
select exists(select from pg_class c where c.oid = 'pg_temp.cats'::regclass);

-- mock for table cat_toys
select exists(select from pg_class c where c.oid = 'pg_temp.cat_toys'::regclass);

-- mock for trigger function cats_aid
select exists(select from pg_proc p where p.oid = 'pg_temp.cats_aid'::regproc);

-- mock for trigger cats_aid_trg
select exists(
    select from pg_trigger t
    where t.tgrelid = 'pg_temp.cats'::regclass
        and t.tgname = 'cats_aid_trg'
        and t.tgfoid = 'pg_temp.cats_aid'::regproc
);

-- test for after insert
insert into pg_temp.cats (cat_name) values ('Barsik');

select exists(
    select from pg_temp.cat_toys ct
        join pg_temp.cats c on (c.cat_id = ct.cat_id)
    where ct.toy_name = format('Toy for %s', c.cat_name)
);

select pg_temp.teardown();

-- context is empty after pg_temp.teardown() call
select * from pg_temp.cats;

select * from pg_temp.cat_toys;

rollback;