begin;

select plan(2);

select collect_tap(
    has_schema('pgmock', 'Схема для расширения присутствует'),
    has_function(
        'pgmock',
        'mock',
        array['jsonb'],
        'Основная функция расширения присутствует'
    )
);

select * from finish();

rollback;