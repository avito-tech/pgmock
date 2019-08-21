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

select pgmock.mock($$"${'public.foo()'::regprocedure}"$$);

select public.foo() = pg_temp.foo();

select pgmock.mock($$"${'public.foo(integer)'::regprocedure}"$$);

select public.foo(8) = pg_temp.foo(8);