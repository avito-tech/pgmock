-- valid queries
select pgmock._validate_query('123');

select pgmock._validate_query($$"${'some_schema.some_table'::regclass}"$$);

select pgmock._validate_query($$"${'some_schema.some_proc'::regproc}"$$);

select pgmock._validate_query($${ "oid": 123 }$$);

select pgmock._validate_query($${ "oid": "${'some_schema.some_table'::regclass}" }$$);

select pgmock._validate_query($${ "oid": "${'some_schema.some_proc'::regproc}" }$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_proc'::regproc}",
        "mock_name": "some_proc_mock_name"
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "constraints": ["constraint_name"]
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "not_nulls": ["column_name1", "column_name2"]
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "defaults": ["column_name1", "column_name2"]
    }
$$);

select pgmock._validate_query($$
    {
        "constant_functions": [{
            "name": "CONSTANT_FUNCTION_NAME",
            "value": "42"
        }]
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "triggers": [{
            "name": "some_trigger_name",
            "procedure": "${'some_schema.some_trigger_procedure'::regclass}"
        }]
    }
$$);

-- invalid queries
\set VERBOSITY terse

select pgmock._validate_query('-123');

select pgmock._validate_query($$"incorrect string"$$);

select pgmock._validate_query($${ "oid": -123 }$$);

select pgmock._validate_query($${ "oid": 123.42 }$$);

select pgmock._validate_query($${ "oid": "incorrect string" }$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_proc'::regproc}",
        "mock_name": "invalid mock name"
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "constraints": "constraint_name"
    }
$$);

select pgmock._validate_query($$
    {
        "oid": "${'some_schema.some_table'::regclass}",
        "constraints": ["invalid constraint name"]
    }
$$);

select pgmock._validate_query($$
    {
        "constant_functions": [{
            "name": "INVALID NAME",
            "value": "42"
        }]
    }
$$);

select pgmock._validate_query($$
    {
        "constant_functions": { "name": "INVALID NAME", "value": "42" }
    }
$$);