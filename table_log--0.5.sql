--
-- table_log () -- log changes to another table
--
--
-- see README.table_log for details
--
--
-- written by Andreas ' ads' Scherbaum (ads@pgug.de)
--
--

-- create function

CREATE FUNCTION table_log ()
    RETURNS TRIGGER
    AS 'MODULE_PATHNAME' LANGUAGE C;
CREATE FUNCTION "table_log_restore_table" (VARCHAR, VARCHAR, CHAR, CHAR, CHAR, TIMESTAMPTZ, CHAR, INT, INT)
    RETURNS VARCHAR
    AS 'MODULE_PATHNAME', 'table_log_restore_table' LANGUAGE C;
CREATE FUNCTION "table_log_restore_table" (VARCHAR, VARCHAR, CHAR, CHAR, CHAR, TIMESTAMPTZ, CHAR, INT)
    RETURNS VARCHAR
    AS 'MODULE_PATHNAME', 'table_log_restore_table' LANGUAGE C;
CREATE FUNCTION "table_log_restore_table" (VARCHAR, VARCHAR, CHAR, CHAR, CHAR, TIMESTAMPTZ, CHAR)
    RETURNS VARCHAR
    AS 'MODULE_PATHNAME', 'table_log_restore_table' LANGUAGE C;
CREATE FUNCTION "table_log_restore_table" (VARCHAR, VARCHAR, CHAR, CHAR, CHAR, TIMESTAMPTZ)
    RETURNS VARCHAR
    AS 'MODULE_PATHNAME', 'table_log_restore_table' LANGUAGE C;

CREATE OR REPLACE FUNCTION table_log_init(int, text, text, text, text, text DEFAULT 'SINGLE') RETURNS void AS
$table_log_init$
DECLARE
    level        ALIAS FOR $1;
    orig_schema  ALIAS FOR $2;
    orig_name    ALIAS FOR $3;
    log_schema   ALIAS FOR $4;
    log_name     ALIAS FOR $5;
    do_log_user  int = 0;
    level_create text = '';
    orig_qq      text;
    log_qq       text;
    partition_mode ALIAS FOR $6;
    num_log_tables integer;
BEGIN
    -- Quoted qualified names
    orig_qq := quote_ident(orig_schema) || '.' ||quote_ident(orig_name);
    log_qq := quote_ident(log_schema) || '.' ||quote_ident(log_name);

    -- Valid partition mode ?
    IF (partition_mode NOT IN ('SINGLE', 'PARTITION')) THEN
        RAISE EXCEPTION 'table_log_init: unsupported partition mode %', partition_mode;
    END IF;

    IF level <> 3 THEN
        level_create := level_create
            || ', trigger_id BIGSERIAL NOT NULL PRIMARY KEY';
        IF level <> 4 THEN
            level_create := level_create
                || ', trigger_user VARCHAR(32) NOT NULL';
            do_log_user := 1;
            IF level <> 5 THEN
                RAISE EXCEPTION
                    'table_log_init: First arg has to be 3, 4 or 5.';
            END IF;
        END IF;
    END IF;

    IF (partition_mode = 'SINGLE') THEN
        EXECUTE  'CREATE TABLE ' || log_qq
              || '(LIKE ' || orig_qq
              || ', trigger_mode VARCHAR(10) NOT NULL'
              || ', trigger_tuple VARCHAR(5) NOT NULL'
              || ', trigger_changed TIMESTAMPTZ NOT NULL'
              || level_create
              || ')';

    ELSE
        -- Partitioned mode requested...
        EXECUTE  'CREATE TABLE ' || log_qq || '_0'
              || '(LIKE ' || orig_qq
              || ', trigger_mode VARCHAR(10) NOT NULL'
              || ', trigger_tuple VARCHAR(5) NOT NULL'
              || ', trigger_changed TIMESTAMPTZ NOT NULL'
              || level_create
              || ')';

        EXECUTE  'CREATE TABLE ' || log_qq || '_1'
              || '(LIKE ' || orig_qq
              || ', trigger_mode VARCHAR(10) NOT NULL'
              || ', trigger_tuple VARCHAR(5) NOT NULL'
              || ', trigger_changed TIMESTAMPTZ NOT NULL'
              || level_create
              || ')';

        EXECUTE 'CREATE VIEW ' || log_qq || '_v'
              || ' AS SELECT * FROM ' || log_qq || '_0 UNION ALL '
              || 'SELECT * FROM ' || log_qq || '_1';
    END IF;


    EXECUTE 'CREATE TRIGGER "table_log_trigger" AFTER UPDATE OR INSERT OR DELETE ON '
            || orig_qq || ' FOR EACH ROW EXECUTE PROCEDURE table_log('
            || quote_literal(log_name) || ','
            || do_log_user || ','
            || quote_literal(log_schema) || ','
            || quote_literal(partition_mode)
            || ')';

    RETURN;
END;
$table_log_init$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION table_log_init(int, text) RETURNS void AS '
DECLARE
    level        ALIAS FOR $1;
    orig_name    ALIAS FOR $2;
BEGIN
    PERFORM table_log_init(level, orig_name, current_schema());
    RETURN;
END;
' LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION table_log_init(int, text, text) RETURNS void AS '
DECLARE
    level        ALIAS FOR $1;
    orig_name    ALIAS FOR $2;
    log_schema   ALIAS FOR $3;
BEGIN
    PERFORM table_log_init(level, current_schema(), orig_name, log_schema);
    RETURN;
END;
' LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION table_log_init(int, text, text, text) RETURNS void AS '
DECLARE
    level        ALIAS FOR $1;
    orig_schema  ALIAS FOR $2;
    orig_name    ALIAS FOR $3;
    log_schema   ALIAS FOR $4;
BEGIN
    PERFORM table_log_init(level, orig_schema, orig_name, log_schema,
        CASE WHEN orig_schema=log_schema
            THEN orig_name||''_log'' ELSE orig_name END);
    RETURN;
END;
' LANGUAGE plpgsql;
