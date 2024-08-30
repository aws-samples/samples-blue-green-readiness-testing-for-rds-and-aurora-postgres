WITH no_primary_key_or_replica_identity AS (
    SELECT 
        n.nspname AS schema_name,
        c.relname AS table_name,
        'Missing primary key or replica identity' AS reason
    FROM 
        pg_class c
    JOIN 
        pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN 
        pg_index i ON i.indrelid = c.oid AND i.indisprimary
    WHERE 
        c.relkind = 'r'  -- Only ordinary tables
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        AND (i.indisprimary IS NULL OR c.relreplident = 'd')  -- Missing primary key or default replica identity
),
pg_largeobject_tables AS (
    SELECT 
        'pg_catalog' AS schema_name,
        'pg_largeobject' AS table_name,
        'Contains pg_largeobject' AS reason
),
foreign_tables AS (
    SELECT 
        table_schema AS schema_name,
        table_name,
        'Foreign table' AS reason
    FROM 
        information_schema.tables 
    WHERE 
        table_type = 'FOREIGN' 
        AND table_schema NOT IN ('pg_catalog', 'information_schema')
)
SELECT * FROM no_primary_key_or_replica_identity
UNION ALL
SELECT * FROM pg_largeobject_tables
UNION ALL
SELECT * FROM foreign_tables
ORDER BY schema_name, table_name;

