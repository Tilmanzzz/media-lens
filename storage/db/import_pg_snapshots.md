# 1. Verbindungen kappen

docker exec media-lens-postgres-1 psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='media_lens' AND pid <> pg_backend_pid();"

# 2. Datenbank löschen und neu erstellen

docker exec media-lens-postgres-1 psql -U postgres -c "DROP DATABASE media_lens;"
docker exec media-lens-postgres-1 psql -U postgres -c "CREATE DATABASE media_lens;"

# 3. SQL-Dump importieren

sed 's/OWNER TO admin/OWNER TO postgres/g' "./storage/db/pg_snapshots/{filename}.sql" | sed '/^\\restrict/d' | sed '/^\\unrestrict/d' | docker exec -i media-lens-postgres-1 psql -U postgres -d media_lens
