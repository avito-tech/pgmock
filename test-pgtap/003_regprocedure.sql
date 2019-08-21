begin;

create function public.foo() returns integer language plpgsql as
$func$
begin
    return 42;
end;
$func$;

create function public.foo(param integer) returns integer language plpgsql as
$func$
begin
    return param;
end;
$func$;

select plan(4);

select pgmock.mock($$"${'public.foo()'::regprocedure}"$$);

select is(
    pg_temp.foo(),
    public.foo(),
    'Генерация заглушки для версии функции без параметров'
);

select pgmock.mock($$"${'public.foo(integer)'::regprocedure}"$$);

select is(
    pg_temp.foo(d.random_int),
    public.foo(d.random_int),
    'Генерация заглушки для версии функции с параметрами'
) from (values (round(random() * 100)::integer)) as d (random_int);

select pgmock.mock($$
    [
        {
            "oid": "${'public.foo()'::regprocedure}",
            "mock_name": "foo_without_parameters"
        },
        {
            "oid": "${'public.foo(integer)'::regprocedure}",
            "mock_name": "foo_with_parameters"
        }
    ]
$$);

select collect_tap(
    is(
        pg_temp.foo_without_parameters(),
        public.foo(),
        'Генерация заглушек для двух перегрузок одной функции (без параметров)'
    ),
    is(
        pg_temp.foo_with_parameters(d.random_int),
        public.foo(d.random_int),
        'Генерация заглушек для двух перегрузок одной функции (с параметром)'
    )
) from (values (round(random() * 100)::integer)) as d (random_int);

select * from finish();

rollback;