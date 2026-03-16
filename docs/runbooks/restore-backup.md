# Runbook: Restore a Database Backup

## When to Use

- Data corruption or accidental deletion
- Rolling back to a known-good state
- Migrating data between servers

## Prerequisites

- SSH access as the `deploy` user
- Backups exist in `/data/backups/postgres/`

## Steps

### 1. List available backups

```bash
ssh deploy@YOUR_SERVER_IP
ls -lh /data/backups/postgres/
```

Backups follow the naming pattern `<database>_YYYYMMDD_HHMMSS.sql.gz`. The backup cron runs daily at 02:00 UTC with 7-day retention.

### 2. Choose a backup

Identify the backup file to restore. Example:

```
todo_app_db_20260315_020001.sql.gz
```

### 3. Run the restore script

Interactive mode (prompts for confirmation):

```bash
bash /opt/platform/infrastructure/restore-postgres.sh
```

The script will list available backups and prompt you to select one.

Non-interactive mode (for scripting):

```bash
bash /opt/platform/infrastructure/restore-postgres.sh --yes <backup-file>
```

### 4. Verify the restored data

Connect to the database and check key tables:

```bash
docker exec -i platform-postgres-1 psql -U postgres -d <database_name> -c "\dt"
docker exec -i platform-postgres-1 psql -U postgres -d <database_name> -c "SELECT count(*) FROM <table_name>;"
```

### 5. Restart the application

After restoring, restart the app to ensure it reconnects cleanly:

```bash
cd /opt/apps/<app-name>
docker compose -p <app-name> -f deploy/docker-compose.yml restart app
```

### 6. Verify the application

```bash
curl -s https://<app-domain>/health
```

## Important Notes

- **Restoring drops the existing database** and recreates it from the backup. All data written after the backup was taken will be lost.
- Backups are retained for 7 days. If you need a backup older than 7 days, you must have configured off-server backup sync (e.g., via `rclone`).
- The restore script operates on the platform PostgreSQL instance. It does not affect other databases on the same instance.
- Consider stopping the application before restoring to avoid write conflicts:
  ```bash
  docker compose -p <app-name> -f deploy/docker-compose.yml stop app
  # ... restore ...
  docker compose -p <app-name> -f deploy/docker-compose.yml start app
  ```
