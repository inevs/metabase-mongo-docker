# Server Migration Guide

This guide explains how to migrate your IT Agile Controlling Docker setup to a new server.

## Overview

The migration involves:
1. Creating a backup of the current MongoDB data
2. Transferring files to the new server
3. Setting up Docker environment on new server
4. Restoring data from backup

## Prerequisites

- Docker and Docker Compose installed on both servers
- SSH access to both servers
- Sufficient disk space for backup files

## Step 1: Create Backup (Old Server)

1. Navigate to your project directory:
   ```bash
   cd /path/to/it-agile-controlling
   ```

2. Ensure Docker services are running:
   ```bash
   docker compose up -d
   ```

3. Create the backup:
   ```bash
   ./scripts/backup_mongodb.sh
   ```

   This creates a compressed backup file in `backups/mongodb_backup_YYYYMMDD_HHMMSS.tar.gz`

## Step 2: Transfer Files to New Server

1. Copy the entire project directory to the new server:
   ```bash
   # From old server
   rsync -avz --progress /path/to/it-agile-controlling/ user@newserver:/path/to/it-agile-controlling/
   ```

   Or alternatively, copy individual components:
   ```bash
   # Project files
   scp -r /path/to/it-agile-controlling/ user@newserver:/path/to/

   # Or just the essentials if you have the code in git:
   scp /path/to/it-agile-controlling/.env user@newserver:/path/to/it-agile-controlling/
   scp /path/to/it-agile-controlling/backups/*.tar.gz user@newserver:/path/to/it-agile-controlling/backups/
   ```

## Step 3: Setup New Server

1. SSH to the new server:
   ```bash
   ssh user@newserver
   ```

2. Navigate to the project directory:
   ```bash
   cd /path/to/it-agile-controlling
   ```

3. Verify environment configuration:
   ```bash
   cat .env
   ```

4. Start Docker services:
   ```bash
   docker compose up -d
   ```

5. Wait for MongoDB to initialize (check logs):
   ```bash
   docker compose logs -f mongodb
   ```

## Step 4: Restore Data

1. List available backups:
   ```bash
   ./scripts/restore_mongodb.sh
   ```

2. Restore from your backup:
   ```bash
   ./scripts/restore_mongodb.sh mongodb_backup_YYYYMMDD_HHMMSS
   ```

3. Verify the restoration:
   ```bash
   # Check MongoDB connection
   docker exec controlling-mongodb mongosh -u admin -p --authenticationDatabase admin

   # In mongosh, check your data:
   use controlling_db
   db.deals.countDocuments()
   show collections
   ```

## Step 5: Verify Migration

1. **Test Metabase Access:**
   - Open http://newserver:3000
   - Verify dashboards and data connections work

2. **Test MongoDB Express:**
   - Open http://newserver:8081
   - Browse collections and verify data

3. **Run Sample Queries:**
   ```bash
   # Test deals collection
   docker exec controlling-mongodb mongosh \
     -u admin -p --authenticationDatabase admin \
     --eval "db.getSiblingDB('controlling_db').deals.find().limit(5).pretty()"
   ```

## Rollback Plan

If migration fails, you can:

1. Keep the old server running until new server is verified
2. Use the backup files to restore to original state if needed
3. Redirect traffic back to old server

## Troubleshooting

### MongoDB Connection Issues
```bash
# Check container status
docker compose ps

# Check MongoDB logs
docker compose logs mongodb

# Test connection manually
docker exec controlling-mongodb mongosh --eval "db.adminCommand('ping')"
```

### Permission Issues
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Check backup directory permissions
ls -la backups/
```

### Metabase Issues
```bash
# Reset Metabase if needed
docker compose down
docker volume rm controlling_metabase_data
docker compose up -d
```

## Post-Migration Cleanup

1. **Update DNS/Load Balancer** to point to new server
2. **Update monitoring** and backup schedules
3. **Remove old server** after verification period
4. **Update documentation** with new server details

## Backup Schedule Recommendation

Set up automated backups on the new server:

```bash
# Add to crontab (daily backup at 2 AM)
0 2 * * * cd /path/to/it-agile-controlling && ./scripts/backup_mongodb.sh

# Weekly cleanup of old backups (keep last 30 days)
0 3 * * 0 find /path/to/it-agile-controlling/backups -name "*.tar.gz" -mtime +30 -delete
```

## Security Considerations

- Change default passwords in `.env` file
- Ensure firewall rules are properly configured
- Consider using Docker secrets for production
- Regular security updates for the host system