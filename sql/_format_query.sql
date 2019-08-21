select pgmock._format_query('123');

select pgmock._format_query($$"${'schema_name.table_name'::regclass}"$$);

select pgmock._format_query($${"oid": 123}$$);

select pgmock._format_query($${"oid": "${'schema_name.table_name'::regclass}"}$$);
