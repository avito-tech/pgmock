-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgmock" to load this file. \quit

set local check_function_bodies to false;

create type _mock_query as (query jsonb, parsed_nodes jsonb[]);


create type _mock_plan as (query jsonb, mock_definition text[]);


create function mock(
    query jsonb
) returns void strict volatile language sql as
$func$
    select @extschema@._execute(@extschema@._explain(@extschema@._parse(query)));
$func$;


create function _parse(
    query jsonb
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select case when pq.query is null then pqcf else pq end
    from @extschema@._parse_constant_functions(query) pqcf
        join lateral @extschema@._parse(pqcf) pq on true;
$func$;


create function _explain(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_plan immutable strict language sql as
$func$
    select row(
        mock_query.query,
        @extschema@._explain_constant_functions(mock_query.query)
            || @extschema@._explain(mock_query.query)
            || @extschema@._explain_setup(mock_query.query)
            || @extschema@._explain_teardown(mock_query.parsed_nodes)
    )::@extschema@._mock_plan;
$func$;


create function _execute(
    mock_plan @extschema@._mock_plan
) returns void volatile strict language plpgsql as
$func$
declare
    v_mock_definition text;
begin
    foreach v_mock_definition in array mock_plan.mock_definition loop
        execute v_mock_definition;
    end loop;
end;
$func$;


create function _parse_constant_functions(
    query jsonb
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select @extschema@._mock_query(
        @extschema@._jsonb_set(
            query, 'constant_functions', array_to_json(array_agg(cfp))::jsonb
        )
    ) from jsonb_array_elements(query->'constant_functions') cf
        join lateral @extschema@._parse_constant_function_returns(cf) cfp on true;
$func$;


create function _parse(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select case when jsonb_typeof(mock_query.query) = 'array'
        then @extschema@._parse_array(mock_query)
        else @extschema@._parse_nonarray(mock_query)
    end;
$func$;


create function _parse_array(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language plpgsql as
$func$
declare
    v_query          jsonb;
    v_parsed_queries jsonb[];
    v_mock_query     @extschema@._mock_query;
begin
    v_mock_query := mock_query;

    for v_query in select jsonb_array_elements(mock_query.query) loop
        v_mock_query := @extschema@._parse(@extschema@._mock_query(
            v_query, v_mock_query.parsed_nodes
        ));
        v_parsed_queries := v_parsed_queries || v_mock_query.query;
    end loop;

    v_mock_query.query := array_to_json(v_parsed_queries);

    return v_mock_query;
end;
$func$;


create function _parse_nonarray(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select mqord
    from @extschema@._validate_query(mock_query.query) vq
        join lateral @extschema@._format_query(vq) fq on true
        join lateral @extschema@._parse_object(
            @extschema@._mock_query(fq, mock_query.parsed_nodes)
        ) mqo on true
        join lateral @extschema@._reuse_existing_object_if_parsed(mqo) mqor on true
        join lateral @extschema@._parse_dependencies(mqor) mqord on true;
$func$;


create function _format_query(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select case when jsonb_typeof(query) in ('number', 'string')
        then json_build_object('oid', query)::jsonb
        else query
    end;
$func$;


create function _mock_query(
    query        jsonb,
    parsed_nodes jsonb[] default array[]::jsonb[]
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select row(query, parsed_nodes)::@extschema@._mock_query;
$func$;


create function _explain(
    query jsonb
) returns text[] immutable strict language sql as
$func$
    select case when jsonb_typeof(query) = 'array' then (
            select array_agg(md)
            from jsonb_array_elements(query) nmq
                join lateral @extschema@._explain(nmq) nmp on true
                join lateral unnest(nmp) md on true
        ) when not coalesce((query->>'reuse_existing')::boolean, false) then
            @extschema@._explain(query->'dependencies')
                || @extschema@._get_mock_definition(query)
    end;
$func$;


create function _get_mock_definition(
    query jsonb
) returns text[] immutable strict language sql as
$func$
    select case query->>'type'
        when 'table'    then @extschema@._get_table_mock_definition(query)
        when 'function' then @extschema@._get_function_mock_definition(query)
    end;
$func$;


create function _get_function_mock_definition(
    query jsonb
) returns text[] immutable strict language sql as
$func$
    select array[@extschema@._substitute_dependent_objects(query, f.md)]
    from pg_get_functiondef((query->>'oid')::oid) f (md)
$func$;


create function _substitute_dependent_objects(
    query           jsonb,
    mock_definition text
) returns text immutable strict language plpgsql as
$func$
declare
    v_md text;
begin
    if jsonb_typeof(query) = 'array' then
        declare
            v_q jsonb;
        begin
            v_md := mock_definition;
            for v_q in select jsonb_array_elements(query) loop
                v_md := @extschema@._substitute_dependent_objects(v_q, v_md);
            end loop;
        end;
    else
        v_md := regexp_replace(
            mock_definition,
            E'\\y' || (query->>'full_name') || E'\\y',
            query->>'mock_full_name',
            'g'
        );
    end if;

    return coalesce(
        @extschema@._substitute_dependent_objects(query->'dependencies', v_md),
        v_md
    );
end;
$func$;


create type _validation_error as (error_reason text, hint text);


create function _validation_error(
    error_reason text,
    hint         text
) returns @extschema@._validation_error immutable strict language sql as
$func$
    select row(error_reason, hint)::@extschema@._validation_error;
$func$;


create function _is_oid_valid(
    query jsonb
) returns boolean immutable language sql as
$func$
    select case jsonb_typeof(query)
        when 'number' then
                query::text::numeric > 0
            and query::text::numeric = trunc(query::text::numeric)
        when 'string' then
            trim(query::text, '"') ~ $$\$\{'(.*)'::(regclass|regproc|regprocedure)\}$$
        when 'object' then
                query ? 'constant_functions' and not query ? 'oid'
            or  query ? 'oid' and @extschema@._is_oid_valid(query->'oid')
        else false
    end;
$func$;


create function _is_simple_name(
    name text
) returns boolean immutable strict language sql as
$func$
    select name ~ '^[a-zA-Z_][a-zA-Z0-9_]*$' and length(name) < 63;
$func$;


create function _is_mock_name_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select case
        when jsonb_typeof(query) = 'object' then
                query ? 'mock_name'
            and @extschema@._is_simple_name(query->>'mock_name')
            or  not query ? 'mock_name'
        else true
    end;
$func$;


create function _is_array_of_simple_names(
    query jsonb,
    array_name text
) returns boolean immutable strict language sql as
$func$
    select case
        when jsonb_typeof(query) = 'object' and query ? array_name then
                jsonb_typeof(query->array_name) = 'array'
            and (
                select bool_and(@extschema@._is_simple_name(element))
                from jsonb_array_elements_text(query->array_name) element
            )
        else true
    end;
$func$;


create function _is_constraints_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select @extschema@._is_array_of_simple_names(query, 'constraints');
$func$;


create function _is_not_nulls_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select @extschema@._is_array_of_simple_names(query, 'not_nulls');
$func$;


create function _is_defaults_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select @extschema@._is_array_of_simple_names(query, 'defaults');
$func$;


create function _is_constant_functions_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select query ? 'constant_functions'
        and jsonb_typeof(query->'constant_functions') = 'array'
        and not exists (
            select from jsonb_array_elements(query->'constant_functions') cf
            where not(
                        cf ? 'name'
                    and @extschema@._is_simple_name(cf->>'name')
                    and cf ? 'value'
                )
        )
        or not query ? 'constant_functions';
$func$;


create function _is_triggers_valid(
    query jsonb
) returns boolean immutable strict language sql as
$func$
    select query ? 'triggers'
        and jsonb_typeof(query->'triggers') = 'array'
        and not exists (
            select from jsonb_array_elements(query->'triggers') tg
            where not (
                    tg ? 'name'
                and @extschema@._is_simple_name(tg->>'name')
                and tg ? 'procedure'
                and (@extschema@._validate_query(tg->'procedure') is not null)
            )
        )
        or not query ? 'triggers';
$func$;


create function _check_for_unknown_params(
    query jsonb
) returns void immutable language plpgsql as
$func$
declare
    KNOWN_PARAMS constant text[] := array[
        'oid', 'mock_name', 'constraints', 'dependencies', 'not_nulls',
        'defaults', 'constant_functions', 'triggers'
    ];
    v_unknown_params text;
begin
    v_unknown_params := (
        select string_agg(key, ', ') as unknown_params
        from jsonb_each(query)
            left join unnest(KNOWN_PARAMS) kp on (kp = key)
        where kp is null
            and jsonb_typeof(query) = 'object'
    );

    if v_unknown_params is not null then
        raise warning using
            message = format(
                'Unknown (sub)query params "%s": %L',
                v_unknown_params,
                query
            ),
            errcode = 'PM000';
    end if;
end;
$func$;


create function _validate_query(
    query jsonb
) returns jsonb immutable strict language plpgsql as
$func$
declare
    v_validation_error @extschema@._validation_error;
begin
    perform @extschema@._check_for_unknown_params(query);

    v_validation_error := case
        when not @extschema@._is_oid_valid(query) then
            @extschema@._validation_error(
                'Invalid oid',
                'Please check documentation for supported oid format'
            )
        when not @extschema@._is_mock_name_valid(query) then
            @extschema@._validation_error(
                'Invalid mock name',
                'Please check documentation for supported mock name format'
            )
        when not @extschema@._is_constraints_valid(query) then
            @extschema@._validation_error(
                'Invalid constraints',
                'Please check documentation for supported constraints format'
            )
        when not @extschema@._is_not_nulls_valid(query) then
            @extschema@._validation_error(
                'Invalid not nulls',
                'Please check documentation for supported not nulls format'
            )
        when not @extschema@._is_defaults_valid(query) then
            @extschema@._validation_error(
                'Invalid defaults',
                'Please check documentation for supported defaults format'
            )
        when not @extschema@._is_constant_functions_valid(query) then
            @extschema@._validation_error(
                'Invalid constant functions',
                'Please check documentation for supported constant functions format'
            )
        when not @extschema@._is_triggers_valid(query) then
            @extschema@._validation_error(
                'Invalid triggers',
                'Please check documentation for supported triggers format'
            )
    end;

    if v_validation_error.error_reason is not null then
        raise exception using
            message = format(
                'Invalid mock (sub)query %L: %s',
                query,
                v_validation_error.error_reason
            ),
            errcode = 'PM001',
            hint    = v_validation_error.hint || E'\n';
    end if;

    return _validate_query.query;
end;
$func$;


create function _jsonb_remove_keys(
    target jsonb,
    key    text[]
) returns jsonb immutable language sql as
$func$
    select coalesce(json_object_agg(t.key, t.value)::jsonb, target)
    from jsonb_each(target) t
        join unnest(_jsonb_remove_keys.key) p (key) on (t.key != p.key)
    where jsonb_typeof(target) = 'object';
$func$;


create function _jsonb_set(
    target jsonb,
    key    text,
    value  jsonb
) returns jsonb immutable language sql as
$func$
    select coalesce(json_object_agg(x.key, x.value)::jsonb, target)
    from (
        select t.key, t.value
        from jsonb_each(@extschema@._jsonb_remove_keys(target, array[key])) t
        union all
        select key, value
    ) x
    where jsonb_typeof(target) = 'object' and _jsonb_set.value is not null;
$func$;


create function _parse_oid_and_type(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    with w_parsed_oid as (
        select case
            when query->>'oid' ilike '%::regprocedure%' then object::regprocedure::oid
            when query->>'oid' ilike '%::regproc%'      then object::regproc::oid
            when query->>'oid' ilike '%::regclass%'     then object::regclass::oid
            else (query->>'oid')::oid
        end as parsed_oid
        from regexp_matches(query->>'oid', $$\$\{'(.*)'::.*\}$$) matches
            join lateral unnest(matches) object on true
    ), w_parsed_type as (
        select case
            when c.oid is not null then 'table'
            when p.oid is not null then 'function'
            else 'unknown'
        end as parsed_type
        from w_parsed_oid wpo
            left join pg_class c on (c.oid = wpo.parsed_oid)
            left join pg_proc p on (p.oid = wpo.parsed_oid)
    )
    select @extschema@._jsonb_set(
        target := @extschema@._jsonb_set(query, 'oid', to_json(po.parsed_oid)::jsonb),
        key    := 'type',
        value  := to_json(pt.parsed_type)::jsonb
    ) from w_parsed_oid po cross join w_parsed_type pt;
$func$;


create function _describe_object(
    query       jsonb,
    schema_name text,
    name        text
) returns jsonb immutable strict language sql as
$func$
    select qmfn
    from @extschema@._jsonb_set(
            query, 'full_name', to_json(format('%I.%I', schema_name, name))::jsonb
        ) qfn join lateral @extschema@._jsonb_set(
            qfn, 'mock_full_name', to_json(
                format('pg_temp.%I', coalesce(query->>'mock_name', name))
            )::jsonb
        ) qmfn on true;
$func$;


create function _parse_table_structure(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select @extschema@._jsonb_set(
        query, 'columns', array_to_json(array_agg(json_build_object(
            'num', a.attnum,
            'name', a.attname,
            'type', a.atttypid::regtype::text
        ) order by a.attnum asc))::jsonb
    ) from pg_attribute a
    where a.attrelid = (query->>'oid')::oid
        and not a.attisdropped
        and a.attnum > 0;
$func$;


create function _parse_table_not_nulls(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select @extschema@._jsonb_set(
        target := @extschema@._jsonb_remove_keys(query, array['not_nulls']),
        key    := 'columns',
        value  := array_to_json(array_agg(
            case when n.name is not null
                then @extschema@._jsonb_set(c, 'not_null', to_json(true)::jsonb)
                else c
            end))::jsonb
    ) from jsonb_array_elements(query->'columns') c
        left join jsonb_array_elements_text(
            query->'not_nulls'
        ) n (name) on (n.name = (c->>'name'))
    where query ? 'not_nulls';
$func$;


create function _parse_table_constraints(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select @extschema@._jsonb_set(
        query, 'constraints', array_to_json(array_agg(json_build_object(
            'name',       c.conname,
            'definition', pg_get_constraintdef(c.oid)
        )))::jsonb
    ) from pg_constraint c
    where c.conrelid = (query->>'oid')::oid
        and c.contype in ('p', 'c', 'u')
        and c.conname in (select jsonb_array_elements_text(query->'constraints'));
$func$;


create function _parse_table_defaults(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select @extschema@._jsonb_set(
        target := @extschema@._jsonb_remove_keys(query, array['defaults']),
        key    := 'columns',
        value  := array_to_json(array_agg(
            case when ad.adsrc is not null
                then @extschema@._jsonb_set(c, 'default', to_json(ad.adsrc)::jsonb)
                else c
            end))::jsonb
    ) from jsonb_array_elements(query->'columns') c
        left join jsonb_array_elements_text(query->'defaults') d (name) on (d.name = (c->>'name'))
        left join pg_attrdef ad on (
            ad.adrelid = (query->>'oid')::oid
            and ad.adnum = (c->>'num')::smallint
            and d.name is not null
        )
    where query ? 'defaults';
$func$;


create function _parse_table_triggers(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language plpgsql as
$func$
declare
    LEVEL_ROW      constant smallint := 1;
    WHEN_BEFORE    constant smallint := 2;
    EVENT_INSERT   constant smallint := 4;
    EVENT_DELETE   constant smallint := 8;
    EVENT_UPDATE   constant smallint := 16;
    EVENT_TRUNCATE constant smallint := 32;

    v_trigger      jsonb;
    v_triggers     jsonb[];
    v_parsed_nodes jsonb[];
begin
    v_parsed_nodes := mock_query.parsed_nodes;

    for v_trigger in
        select tglevel
        from jsonb_array_elements(mock_query.query->'triggers') j (tg)
            join pg_trigger t on (t.tgname = j.tg->>'name')
            join lateral @extschema@._jsonb_set(
                j.tg, 'when', to_json(case when t.tgtype & WHEN_BEFORE != 0
                    then 'BEFORE'
                    else 'AFTER'
                end)::jsonb
            ) tgwhen on true
            join lateral @extschema@._jsonb_set(
                tgwhen, 'event', to_json(array_to_string(array[
                    case when t.tgtype & EVENT_INSERT != 0 then 'INSERT' end,
                    case when t.tgtype & EVENT_DELETE != 0 then 'DELETE' end,
                    case when t.tgtype & EVENT_UPDATE != 0 then 'UPDATE' end,
                    case when t.tgtype & EVENT_TRUNCATE != 0 then 'TRUNCATE' end
                ]::text[], ' OR '))::jsonb
            ) tgevent on true
            join lateral @extschema@._jsonb_set(
                tgevent, 'level', to_json(case when t.tgtype & LEVEL_ROW != 0
                    then 'FOR EACH ROW'
                    else 'FOR EACH STATEMENT'
                end)::jsonb
            ) tglevel on true
        where t.tgrelid = (mock_query.query->>'oid')::oid
    loop
        <<parse_trigger_procedure>>
        declare
            v_trigger_procedure @extschema@._mock_query;
        begin
            v_trigger_procedure := @extschema@._parse_nonarray(
                @extschema@._mock_query(v_trigger->'procedure', v_parsed_nodes)
            );
            v_triggers := v_triggers || @extschema@._jsonb_set(
                v_trigger, 'procedure', v_trigger_procedure.query
            );
            v_parsed_nodes := v_trigger_procedure.parsed_nodes;
        end parse_trigger_procedure;
    end loop;

    return @extschema@._mock_query(
        @extschema@._jsonb_set(
            mock_query.query, 'triggers', array_to_json(v_triggers)::jsonb
        ),
        v_parsed_nodes
    );
end;
$func$;


create function _parse_table(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select tt
    from pg_class c
        join pg_namespace n on (n.oid = c.relnamespace)
        join lateral @extschema@._describe_object(
            mock_query.query, n.nspname, c.relname
        ) tq on true
        join lateral @extschema@._parse_table_structure(tq) ts on true
        join lateral @extschema@._parse_table_not_nulls(ts) tn on true
        join lateral @extschema@._parse_table_constraints(tn) tc on true
        join lateral @extschema@._parse_table_defaults(tc) td on true
        join lateral @extschema@._parse_table_triggers(
            @extschema@._mock_query(td, mock_query.parsed_nodes)
        ) tt on true
    where c.oid = (mock_query.query->>'oid')::oid;
$func$;


create function _parse_function(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$function$
    select @extschema@._mock_query(
        @extschema@._describe_object(mock_query.query, n.nspname, p.proname),
        mock_query.parsed_nodes
    ) from pg_proc p
        join pg_namespace n on (n.oid = p.pronamespace)
    where p.oid = (mock_query.query->>'oid')::oid;
$function$;


create function _parse_object(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query stable strict language sql as
$func$
    select case pmq.query->>'type'
        when 'table'    then @extschema@._parse_table(pmq)
        when 'function' then @extschema@._parse_function(pmq)
    end from @extschema@._mock_query(
        @extschema@._parse_oid_and_type(mock_query.query),
        mock_query.parsed_nodes
    ) pmq;
$func$;


create function _reuse_existing_object_if_parsed(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$func$
    with w_reused_object as (
        select @extschema@._mock_query(
            @extschema@._jsonb_set(pn, 'reuse_existing', to_json(true)::jsonb),
            mock_query.parsed_nodes
        ) as mock_query
        from unnest(mock_query.parsed_nodes) pn
        where (pn->>'oid') = (mock_query.query->>'oid')
    )
    select @extschema@._mock_query(
        coalesce(
            (select (wro.mock_query).query from w_reused_object wro),
            mock_query.query
        ),
        coalesce(
            (select (wro.mock_query).parsed_nodes from w_reused_object wro),
            mock_query.parsed_nodes || @extschema@._jsonb_remove_keys(
                mock_query.query, array['defaults', 'dependencies', 'triggers']
            )
        )
    );
$func$;


create function _parse_dependencies(
    mock_query @extschema@._mock_query
) returns @extschema@._mock_query immutable strict language sql as
$func$
    select @extschema@._mock_query(
        @extschema@._jsonb_set(mock_query.query, 'dependencies', f.query),
        coalesce(f.parsed_nodes, mock_query.parsed_nodes)
    ) from @extschema@._parse(@extschema@._mock_query(
        mock_query.query->'dependencies',
        mock_query.parsed_nodes
    )) f (query, parsed_nodes);
$func$;


create function _parse_constant_function_returns(
    query jsonb
) returns jsonb immutable strict language sql as
$func$
    select @extschema@._jsonb_set(
        query, 'returns', to_json(coalesce(
            query->>'returns',
            case jsonb_typeof(query->'value')
                when 'number' then
                    case when trunc((query->>'value')::numeric)
                        = (query->>'value')::numeric
                        then 'integer'
                        else 'numeric'
                    end
                else 'text'
            end
        ))::jsonb
    );
$func$;


create function _array_to_string(
    target           anyarray,
    delimiter        text,
    element_modifier text default '${element}'
) returns text immutable language sql as
$func$
    select coalesce(
        string_agg(
            replace(element_modifier, '${element}', a.element::text),
            delimiter
        ),
        ''
    ) from unnest(target) a (element);
$func$;


create function _explain_constant_functions(
    query jsonb
) returns text[] immutable strict language sql as
$func$
    select array_agg(format(
        E'CREATE OR REPLACE FUNCTION pg_temp.%1$s()\n'||
        E' RETURNS %2$s\n'||
        E' IMMUTABLE\n'||
        E' LANGUAGE sql AS\n'||
        E'$function$\n'||
        E'    select (%3$s)::%2$s;\n'||
        E'$function$;',
        cf->>'name',
        cf->>'returns',
        quote_literal(cf->>'value')
    )) from jsonb_array_elements(query->'constant_functions') cf;
$func$;


create function _explain_setup(
    query jsonb
) returns text immutable strict language sql as
$func$
    select replace(
        E'CREATE OR REPLACE FUNCTION pg_temp.setup()\n'||
        E' RETURNS void\n'||
        E' LANGUAGE plpgsql AS\n'||
        E'$function$\n'||
        E'begin\n'||
            E'${setup}\n'||
        E'end;\n'||
        E'$function$;',
        '${setup}',
        ''
    );
$func$;


create function _explain_teardown(
    parsed_nodes jsonb[]
) returns text immutable strict language sql as
$func$
    select replace(
        E'CREATE OR REPLACE FUNCTION pg_temp.teardown()\n'||
        E' RETURNS void\n'||
        E' LANGUAGE plpgsql AS\n'||
        E'$BODY$\n'||
        E'BEGIN\n'||
            E'${teardown}\n'||
        E'END;\n'||
        E'$BODY$;',
        '${teardown}',
        @extschema@._array_to_string(
            target           := @extschema@._get_mocked_tables(parsed_nodes),
            delimiter        := E'\n',
            element_modifier := '    truncate table ${element};'
        )
    );
$func$;


create function _get_mocked_tables(
    parsed_nodes jsonb[]
) returns text[] immutable strict language sql as
$func$
    select array_agg(node->>'mock_full_name')
    from unnest(parsed_nodes) node
    where (node->>'type') = 'table';
$func$;


create function _get_table_mock_definition(
    query jsonb
) returns text[] immutable strict language sql as
$func$
    select (
        select
            format(E'CREATE TEMPORARY TABLE %s (\n', query->>'mock_full_name') ||
            string_agg(
                format('    %s %s%s%s',
                    j.col->>'name',
                    j.col->>'type',
                    case when (j.col->>'not_null')::boolean then ' NOT NULL' end,
                    coalesce(' DEFAULT '||(j.col->>'default'), '')
                ),
                E',\n'
                order by (j.col->>'num')::smallint asc
            ) || E'\n);'
        from jsonb_array_elements(query->'columns') j (col)
    ) || (
        select array_agg(format(
            'ALTER TABLE %s ADD CONSTRAINT %s %s;',
            query->>'mock_full_name', (j.constr->>'name'), (j.constr->>'definition')
        )) from jsonb_array_elements(query->'constraints') j (constr)
    ) || (
        select array_agg(tfmd)
        from jsonb_array_elements(query->'triggers') j (trg)
            join lateral @extschema@._explain(j.trg->'procedure') etf on true
            join lateral unnest(etf) tfmd on true
    ) || (
        select array_agg(format(
            'CREATE TRIGGER %s %s %s ON %s %s EXECUTE PROCEDURE %s();',
            j.trg->>'name',
            j.trg->>'when',
            j.trg->>'event',
            query->>'mock_full_name',
            j.trg->>'level',
            j.trg->'procedure'->>'mock_full_name'
        )) from jsonb_array_elements(query->'triggers') j (trg)
    );
$func$;