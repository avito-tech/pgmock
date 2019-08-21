begin;

create table public.product_movement(
    movement_id serial  primary key,
    product_id  integer not null,
    movement    integer not null
);

create table public.product_movement_mv(
    product_id integer primary key,
    movement   integer not null
);

create function public.product_movement_aggregator()
    returns void language plpgsql as
$func$
begin
    with w_aggregated_movement as (
        select pm.product_id, sum(pm.movement) as movement
        from public.product_movement pm
        group by pm.product_id
        having sum(pm.movement) != 0
    ), w_deleted_movement as (
        delete from public.product_movement_mv pmm
        where pmm.product_id in (
            select a.product_id
            from w_aggregated_movement a
        )
    )
    insert into public.product_movement_mv (product_id, movement)
    select a.product_id, a.movement from w_aggregated_movement a;
end;
$func$;

insert into public.product_movement (product_id, movement)
values
    (1, 10), (1, 20), (1, 30), (1, -10), (1, -20), (1, -30), (1, 5),
    (2, 10), (2, 10), (2, 10), (2, -10), (2, -10), (2, 15), (2, 10);

insert into public.product_movement_mv (product_id, movement)
values (1, 5), (2, 25);

select pgmock.mock($$
    {
        "oid": "${'public.product_movement_aggregator'::regproc}",
        "dependencies": [
            "${'public.product_movement'::regclass}",
            "${'public.product_movement_mv'::regclass}"
        ]
    }
$$);

select pg_temp.setup();

-- product_movement mock should be empty
select * from pg_temp.product_movement;

-- product_movement_mv mock should be empty
select * from pg_temp.product_movement_mv;

-- product_movement_aggregator mock should
-- aggregate raw values in substituted context
insert into pg_temp.product_movement (product_id, movement)
values
    (1, 10), (1, -8), (1, -2), (1, 5),
    (2, 5), (2, -5), (2, 10), (2, 2),
    (3, 5), (3, -2), (3, -3);

select pg_temp.product_movement_aggregator();

select product_id, movement
from pg_temp.product_movement_mv
order by product_id, movement;

select pg_temp.teardown();

-- table mocks should be empty after pg_temp.teardown() call
select * from pg_temp.product_movement;

select * from pg_temp.product_movement_mv;

rollback;