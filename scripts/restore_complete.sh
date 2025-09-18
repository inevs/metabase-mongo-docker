#!/bin/bash

# Complete Restore Script for Docker Migration
# This script restores both MongoDB data AND Metabase data from a complete backup

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Check if backup name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_name>"
    echo
    echo "Available complete backups:"
    ls -1 "$BACKUP_DIR"/complete_backup_*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz$//' || echo "No complete backups found"
    echo
    echo "Available MongoDB-only backups:"
    ls -1 "$BACKUP_DIR"/mongodb_backup_*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz$//' || echo "No MongoDB backups found"
    exit 1
fi

BACKUP_NAME="$1"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
RESTORE_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    echo
    echo "Available backups:"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz$//' || echo "No backups found"
    exit 1
fi

echo "=== Complete System Restore Script ==="
echo "Date: $(date)"
echo "Backup: $BACKUP_NAME"
echo "Source: $BACKUP_FILE"
echo

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo "Error: .env file not found in $PROJECT_ROOT"
    exit 1
fi

# Default values if not set in .env
MONGO_HOST=${MONGO_HOST:-localhost}
MONGO_PORT=${MONGO_PORT:-27017}
MONGO_ROOT_USERNAME=${MONGO_ROOT_USERNAME:-admin}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-mongo_pw}
MONGO_DATABASE=${MONGO_DATABASE:-controlling_db}

# Extract backup if not already extracted
if [ ! -d "$RESTORE_PATH" ]; then
    echo "Extracting backup archive..."
    cd "$BACKUP_DIR"
    tar -xzf "${BACKUP_NAME}.tar.gz"
fi

# Verify backup contents
if [ ! -f "$RESTORE_PATH/backup_info.txt" ]; then
    echo "Error: Invalid backup format. backup_info.txt not found."
    exit 1
fi

echo "Backup information:"
cat "$RESTORE_PATH/backup_info.txt"
echo

# Determine backup type
BACKUP_TYPE="unknown"
if [ -d "$RESTORE_PATH/mongodb" ] && [ -f "$RESTORE_PATH/metabase_data.tar.gz" ]; then
    BACKUP_TYPE="complete"
elif [ -d "$RESTORE_PATH/$MONGO_DATABASE" ]; then
    BACKUP_TYPE="mongodb_only"
fi

echo "Detected backup type: $BACKUP_TYPE"
echo

# Warning about data replacement
echo "⚠️  WARNING: This will replace ALL application data:"
echo "   - MongoDB database: '$MONGO_DATABASE'"
if [ "$BACKUP_TYPE" = "complete" ]; then
    echo "   - Metabase dashboards, users, and settings"
fi
echo
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Check if containers are running
echo "Checking container status..."
if ! docker compose ps | grep -q "Up"; then
    echo "Starting Docker containers..."
    docker compose up -d
    echo "Waiting for containers to be ready..."
    sleep 10
fi

# 1. RESTORE MONGODB
echo
echo "=== Restoring MongoDB ==="

# Check MongoDB connection
echo "Checking MongoDB connection..."
RETRIES=0
while ! docker exec controlling-mongodb mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "Error: Cannot connect to MongoDB after 30 attempts."
        exit 1
    fi
    echo "Waiting for MongoDB... (attempt $RETRIES/30)"
    sleep 2
done

echo "✓ MongoDB is ready"

# Drop existing database
echo "Dropping existing database '$MONGO_DATABASE'..."
docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').dropDatabase()"

# Determine MongoDB backup path
if [ "$BACKUP_TYPE" = "complete" ]; then
    MONGO_BACKUP_PATH="$RESTORE_PATH/mongodb/backup/$MONGO_DATABASE"
else
    MONGO_BACKUP_PATH="$RESTORE_PATH/$MONGO_DATABASE"
fi

# Copy backup data to container
echo "Copying MongoDB backup data to container..."
docker cp "$MONGO_BACKUP_PATH" controlling-mongodb:/tmp/restore

# Restore database using mongorestore
echo "Restoring MongoDB database..."
docker exec controlling-mongodb mongorestore \
    --host localhost:27017 \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db "$MONGO_DATABASE" \
    /tmp/restore

# Clean up temporary files in container
docker exec controlling-mongodb rm -rf /tmp/restore

# Verify MongoDB restoration
DEALS_COUNT=$(docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').deals.countDocuments({})" 2>/dev/null || echo "0")

echo "✓ MongoDB restored - Deals count: $DEALS_COUNT"

# 2. RESTORE METABASE (if complete backup)
if [ "$BACKUP_TYPE" = "complete" ] && [ -f "$RESTORE_PATH/metabase_data.tar.gz" ]; then
    echo
    echo "=== Restoring Metabase ==="

    # Stop Metabase container to safely restore data
    echo "Stopping Metabase container..."
    docker compose stop metabase

    # Get Metabase volume name
    METABASE_VOLUME=$(docker volume ls | grep metabase | awk '{print $2}')
    if [ -z "$METABASE_VOLUME" ]; then
        METABASE_VOLUME="controlling_metabase_data"
    fi

    echo "Restoring Metabase volume: $METABASE_VOLUME"

    # Remove existing volume content and restore from backup
    docker run --rm \
        -v "$METABASE_VOLUME":/target \
        -v "$RESTORE_PATH":/backup:ro \
        alpine:latest \
        sh -c "rm -rf /target/* /target/.[^.]* && cd /target && tar -xzf /backup/metabase_data.tar.gz"

    # Restart Metabase
    echo "Starting Metabase container..."
    docker compose start metabase

    # Wait for Metabase to be ready
    echo "Waiting for Metabase to start..."
    sleep 15

    echo "✓ Metabase data restored"
    echo "  → Dashboards, questions, and user settings have been restored"
    echo "  → Database connections may need to be verified"
fi

# 3. VERIFY RESTORATION
echo
echo "=== Verification ==="

# Check container status
echo "Container status:"
docker compose ps

# Verify MongoDB collections
COLLECTIONS_COUNT=$(docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').getCollectionNames().length")

echo "MongoDB verification:"
echo "  - Collections restored: $COLLECTIONS_COUNT"
echo "  - Deals documents: $DEALS_COUNT"

# Check if services are accessible
echo
echo "Service availability:"
if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "  ✓ Metabase: http://localhost:3000 (accessible)"
else
    echo "  ⚠ Metabase: http://localhost:3000 (not yet ready - may need a few more minutes)"
fi

if curl -s http://localhost:8081 >/dev/null 2>&1; then
    echo "  ✓ MongoDB Express: http://localhost:8081 (accessible)"
else
    echo "  ⚠ MongoDB Express: http://localhost:8081 (check configuration)"
fi

echo
echo "=== Restore Completed Successfully ==="
echo "System restoration summary:"
echo "  ✓ MongoDB database: $MONGO_DATABASE ($DEALS_COUNT deals)"
if [ "$BACKUP_TYPE" = "complete" ]; then
    echo "  ✓ Metabase application data restored"
    echo "  → Access Metabase at: http://localhost:3000"
    echo "  → Database connections may need verification in Metabase"
fi
echo "  → Access MongoDB Express at: http://localhost:8081"
echo

# Cleanup
read -p "Remove extracted backup directory? (y/n): " cleanup
if [ "$cleanup" = "y" ]; then
    rm -rf "$RESTORE_PATH"
    echo "Cleanup completed."
fi

echo
echo "🎉 Migration completed successfully!"
echo "Your IT Agile Controlling system has been fully restored."

if [ "$BACKUP_TYPE" = "complete" ]; then
    echo
    echo "📊 Next steps:"
    echo "1. Verify Metabase dashboards at http://localhost:3000"
    echo "2. Check MongoDB connections in Metabase admin"
    echo "3. Test a few sample queries to ensure data integrity"
fi