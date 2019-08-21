# pgmock

## Описание
Расширение для PostgreSQL 9.4+ для создания заглушек для юнит-тестов

## Основная идея
Расширение `pgmock` решает задачу изоляции тестируемых хранимых процедур от существующего контекста. По запросу оно создает заглушку для тестируемой хранимой процедуры с подмененным контекстом - тестовым контекстом. По завершению тест-сьюта тестовый контекст автоматически разрушается. Это возможно благодаря транзакционному `DDL`, а также специальной схеме `pg_temp`, в которой и создается тестовый контекст
Расширение имеет всего лишь одну функцию `mock`, которая принимает на вход запрос по созданию тестового контекста в виде `json`-объекта:
```sql
select pgmock.mock($$
    {
        "oid": "${'myfunction'::regproc}",
        "dependencies": ["${'mytable_1'::regclass}", "${'mytable_2'::regclass}"]
    }
$$);
```
В запросе выше создается заглушка для функции `myfunction` с подмененным контекстом - таблицами `mytable_1` и `mytable_2`. Теперь можно тестировать функцию, а точнее созданную вместо неё заглушку `pg_temp.myfunction`, не опасаясь, что изменение данных в таблицах `mytable_1` или `mytable_2` может затронуть ваш тест-сьют
Также при вызове функции `mock` генерируются две специальных функции:
* `pg_temp.setup` - проводит настройку тестового контекста
* `pg_temp.teardown` - проводит очистку тестового контекста

Расширение `pgmock` придерживается следующей философии:
* тестовый контекст создается один раз в рамках тест-сьюта
* тестовый контекст создается в рамках транзакции
* тесты в рамках тест-сьюта должны быть "обернуты" вызовами `pg_temp.setup` и `pg_temp.teardown`, что позволяет им быть контекстно-независимыми

Таким образом, ваш тест-сьют может выглядеть следующим образом:
```sql
begin;

select pgmock.mock($$
    {
        "oid": "${'myfunction'::regproc}",
        "dependencies": ["${'mytable_1'::regclass}", "${'mytable_2'::regclass}"]
    }
$$);

select pg_temp.setup();

insert into pg_temp.mytable_1 (foo) values ('bar');
insert into pg_temp.mytable_2 (foo) values ('baz');

select pg_temp.myfunction() = 'Ожидаемый результат функции на добавленных выше данных';

select pg_temp.teardown();

select pg_temp.setup();

insert into pg_temp.mytable_1 (foo) values ('bar2');
insert into pg_temp.mytable_2 (foo) values ('baz2');

select
    pg_temp.myfunction() = 'Ожидаемый результат функции на других данных'
                           ||' (ранее добавленные данные не помешают тесту,'
                           ||' т.к. функция pg_temp.teardown позаботилась об'
                           ||' очистке тестового контекста';

select pg_temp.teardown();

rollback;
```

## Установка
Сборка `pgmock` из исходников и его установка осуществляются так:
```shell
git clone https://github.com/avito-tech/pgmock.git
cd pgmock
sudo make install
```
После установки прогоните тесты:
```shell
make installcheck
```
Включите `pgmock` для вашей базы данных:
```shell
create schema pgmock;
create extension pgmock with schema pgmock;
```
Установка расширения в свою схему настоятельно рекомендуется. Это позволит избежать конфликтов имен

## Примеры использования
Примеры использования отсортированы от простых к сложным

### Создание заглушки для функции без состояния
Допустим, у нас есть функция `public.universal_answer`:
```sql
create or replace function public.universal_answer()
    returns integer immutable language sql as
$func$
    select 42;
$func$;
```
Тогда создание заглушки для функции будет выглядеть следующим образом:
```sql
select pgmock.mock($$"${'public.universal_answer'::regproc}"$$);
```
Для расшифровывания имен объектов в их идентификаторы используется специальный синтаксис `${'имя объекта'::тип объекта}`. Поддерживаются следующие типы объектов:
* `regproc` - для функций
* `regclass` - для таблиц

После вызова функции `mock` создается заглушка `pg_temp.universal_answer`
```sql
select public.universal_answer() = pg_temp.universal_answer() as is_equal;
 is_equal
----------
 t
```
Также есть возможность создать заглушку с другим именем:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.universal_answer'::regproc}",
        "mock_name": "another_universal_answer"
    }
$$);
```
После вызова функции `mock` создается заглушка `pg_temp.another_universal_answer`

### Создание заглушки для читающей функции
Допустим, мы хотим создать заглушку для функции `public.get_cat_stats`, которая читает данные из таблицы `public.cats`:
```sql
create table public.cats (
    cat_id             serial   primary key,
    cat_name           text     not null,
    cat_age_in_months  smallint not null
);

insert into public.cats (cat_name, cat_age_in_months)
values
    ('Barsik', 12), ('Murzik', 10), ('Luska', 23),
    ('Rijik', 3), ('Snejok', 38), ('Barsik', 8);

create function public.get_cat_stats(
    out oldest_cat_name   text,
    out youngest_cat_name text,
    out min_age_in_months smallint,
    out avg_age_in_months smallint,
    out max_age_in_months smallint
) returns record language plpgsql as
$func$
begin
    select
        first_value(c.cat_name)
            over (order by c.cat_age_in_months desc) as oldest_cat_name,
        first_value(c.cat_name)
            over (order by c.cat_age_in_months asc)  as youngest_cat_name,
        min(c.cat_age_in_months) over ()             as min_age_in_months,
        round(avg(c.cat_age_in_months) over ())      as avg_age_in_months,
        max(c.cat_age_in_months) over ()             as max_age_in_months
    into
        oldest_cat_name,
        youngest_cat_name,
        min_age_in_months,
        avg_age_in_months,
        max_age_in_months
    from
        public.cats c
    limit 1;

    return;
end;
$func$;
```
Запрос создания заглушки будет выглядеть следующим образом:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.get_cat_stats'::regproc}",
        "dependencies": "${'public.cats'::regclass}"
    }
$$);
```
Параметр запроса `dependencies` говорит, что для функции существуют зависимости в виде указанных объектов (в данном случае таблица `public.cats`), поэтому:
1) должны быть созданы заглушки для зависимых объектов
2) использование оригинальных объектов в функции `public.get_cat_stats` должно быть подменено на использование заглушек

В результате будет создана таблица-заглушка `pg_temp.cats` и заглушка для функции `pg_temp.get_cat_stats`. Это позволяет проводить тестирование в изоляции от существующих данных

### Создание заглушки для пишущей функции
Допустим, что у нас есть функция `public.product_movement_aggregator`, которая читает данные из таблицы `public.product_movement`, производит трансформацию считанных данных, а затем записывает их в таблицу `public.product_movement_mv`:
```sql
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
```
Тогда запрос на создание заглушки будет выглядеть следующим образом:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.product_movement_aggregator'::regproc}",
        "dependencies": [
            "${'public.product_movement'::regclass}",
            "${'public.product_movement_mv'::regclass}"
        ]
    }
$$);
```

### Создание заглушки для таблицы с наследованием ограничений целостности
По умолчанию функция `mock` создает заглушку для таблицы только с наследованием структуры таблицы. Допустим, мы хотим создать заглушку для таблицы `public.cats` и унаследовать **некоторые** ограничения целостности:
```sql
create table public.cats (
    cat_id           serial   not null,
    cat_name         text     not null,
    cat_age_in_month smallint not null check (cat_age_in_month > 0),
    is_kitten        boolean  not null,
    constraint cats_pkey primary key (cat_id),
    constraint cats_name_ukey unique (cat_name),
    constraint cats_is_kitten_ck check (
        is_kitten and cat_age_in_month <= 2
        or not is_kitten and cat_age_in_month > 2
    )
);
```
Тогда запрос на создание заглушки будет выглядеть следующим образом:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.cats'::regclass}",
        "constraints": ["cats_pkey", "cats_is_kitten_ck", "cats_name_ukey"],
        "not_nulls": ["cat_name", "cat_age_in_month"]
    }
$$);
```
Функция `mock` создаст заглушку следующего вида:
```shell
\d+ cats
                             Table "pg_temp_3.cats"
      Column      |   Type   | Modifiers | Storage  | Stats target | Description
------------------+----------+-----------+----------+--------------+-------------
 cat_id           | integer  | not null  | plain    |              |
 cat_name         | text     | not null  | extended |              |
 cat_age_in_month | smallint | not null  | plain    |              |
 is_kitten        | boolean  |           | plain    |              |
Indexes:
    "cats_pkey" PRIMARY KEY, btree (cat_id)
    "cats_name_ukey" UNIQUE CONSTRAINT, btree (cat_name)
Check constraints:
    "cats_is_kitten_ck" CHECK (is_kitten AND cat_age_in_month <= 2 OR NOT is_kitten AND cat_age_in_month > 2)
```
Ограничение для колонки `is_kitten` не было унаследовано, т.к. мы этого не просили

Опциональный параметр `constraints` принимает на вход список имен ограничений целостности, которые нужно унаследовать от оригинальной таблицы. Поддерживаются следующие типы ограничений целостности:
* `primary key`
* `unique constraint`
* `check constraint`

`not null` ограничения задаются с помощью опционального параметра `not_nulls`, принимающего на вход список колонок таблицы, для которых нужно унаследовать `not null` ограничение

### Создание заглушки для таблицы с наследованием значений по умолчанию
Аналогично наследованию ограничений целостности также имеется возможность наследования значений по умолчанию для указанных колонок таблицы:
```sql
create table public.cats (
    cat_id     serial                   not null primary key,
    cat_name   text                     not null default 'Kot',
    created_at timestamp with time zone not null default now()
);
```
Запрос может выглядеть следующим образом:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.cats'::regclass}",
        "defaults": ["cat_id", "cat_name", "created_at"]
    }
$$);
```
Функция `mock` создаст заглушку следующего вида:
```shell
\d+ cats
                                                    Table "pg_temp_3.cats"
   Column   |           Type           |                  Modifiers                   | Storage  | Stats target | Description
------------+--------------------------+----------------------------------------------+----------+--------------+-------------
 cat_id     | integer                  | default nextval('cats_cat_id_seq'::regclass) | plain    |              |
 cat_name   | text                     | default 'Kot'::text                          | extended |              |
 created_at | timestamp with time zone | default now()                                | plain    |              |
```

Опциональный параметр `defaults` ожидает список колонок таблицы, для которых необходимо унаследовать значения по умолчанию

### Создание заглушки для триггерной функции
Дальше - больше: создаем заглушку для триггерной функции. Допустим, у нас есть таблица `public.cats`, для которой создан триггер `cats_aid_trg`, заполняющий таблицу `public.cat_toys`:
```sql
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
```
Запрос на создание заглушек для всего этого добра будет выглядеть следующим образом:
```sql
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
```
```shell
\d+ cats
                                          Table "pg_temp_3.cats"
  Column  |  Type   |                  Modifiers                   | Storage  | Stats target | Description
----------+---------+----------------------------------------------+----------+--------------+-------------
 cat_id   | integer | default nextval('cats_cat_id_seq'::regclass) | plain    |              |
 cat_name | text    |                                              | extended |              |
Triggers:
    cats_aid_trg AFTER INSERT OR DELETE ON cats FOR EACH ROW EXECUTE PROCEDURE pg_temp_3.cats_aid()
```
Опциональный параметр `triggers` ожидает массив объектов с описанием триггеров для таблицы. Объект триггера имеет следующие поля:
* `name` - имя оригинального триггера
* `procedure` - запрос на создание заглушки для триггерной функции (в формате обычного запроса на создание заглушки для функции)

### Повторяющиеся зависимости
В данном примере рассмотрим способ создания заглушек когда зависимости повторяются. Например, есть функция `public.set_cat`, которая вызывает две других функции `public.add_cat` и `public.get_cat`, которые в свою очередь пишут и читают таблицу `public.cats`:
```sql
create table public.cats (
    cat_id   serial not null,
    cat_name text   not null unique,
    constraint cats_pkey primary key (cat_id)
);

create function public.add_cat(
    name text
) returns integer volatile language sql as
$func$
    insert into public.cats (cat_name) values (name) returning cat_id;
$func$;

create function public.get_cat(
    name text
) returns integer volatile language sql as
$func$
    select c.cat_id
    from public.cats c
    where c.cat_name = name;
$func$;

create function public.set_cat(
    name text
) returns integer volatile language plpgsql as
$func$
declare
    cat_id integer;
begin
    cat_id := public.get_cat(name);

    if cat_id is null then
        cat_id := public.add_cat(name);
    end if;

    return cat_id;
end;
$func$;

insert into public.cats (cat_name) values ('Barsik'), ('Snezhok'), ('Muska');
```
При этом запрос на создание заглушки хочется написать так, чтобы подзапрос на создание заглушки `public.cats` описывался только один раз. При таких требованиях запрос будет выглядеть следующим образом:
```sql
select pgmock.mock($$
    {
        "oid": "${'public.set_cat'::regproc}",
        "dependencies": [
            {
                "oid": "${'public.add_cat'::regproc}",
                "dependencies": {
                    "oid": "${'public.cats'::regclass}",
                    "mock_name": "cats_mock",
                    "constraints": ["cats_pkey"],
                    "defaults": ["cat_id"]
                }
            },
            {
                "oid": "${'public.get_cat'::regproc}",
                "dependencies": "${'public.cats'::regclass}"
            }
        ]
    }
$$);
```
В подзапросе:
```javascript
{
    "oid": "${'public.get_cat'::regproc}",
    "dependencies": "${'public.cats'::regclass}"
}
```
будет переиспользован запрос на создание заглушки для таблицы `public.cats`. Функция `mock` автоматически переиспользует уже разобранные объекты (различие объектов производится по их `oid`). Разбор зависимых объектов описанных в виде массива производится в соответствии с их индексом в массиве. При иерархическом описании (при помощи параметра `dependencies`) самый глубокий объект разбирается в первую очередь

### Больше примеров
Больше примеров можно найти в тестах к данному расширению, в файлах `_example_*.sql`
