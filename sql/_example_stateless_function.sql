begin;

create or replace function public.universal_answer()
    returns integer immutable language sql as
$func$
    select 42;
$func$;

select pgmock.mock($$"${'public.universal_answer'::regproc}"$$);

select pg_temp.setup();

select pg_temp.universal_answer();

select pg_temp.teardown();

select pgmock.mock($$
    {
        "oid": "${'public.universal_answer'::regproc}",
        "mock_name": "another_universal_answer"
    }
$$);

select pg_temp.setup();

select pg_temp.another_universal_answer();

select pg_temp.teardown();

rollback;