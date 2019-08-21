begin;

select pgmock.mock($$
    {
        "constant_functions": [
            { "name": "DEFAULT_CAT_NAME", "value": "Snezhok" },
            { "name": "DEFAULT_CAT_AGE", "value": 6, "returns": "smallint" },
            { "name": "DEFAULT_MICE_CAUGHT", "value": 128 }
        ]
    }
$$);

select pg_temp.DEFAULT_CAT_NAME();

select pg_temp.DEFAULT_CAT_AGE();

select pg_temp.DEFAULT_MICE_CAUGHT();

rollback;