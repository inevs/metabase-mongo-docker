#!/bin/bash

# MongoDB Restore Script for Docker Migration
# This script restores MongoDB data from a backup created by backup_mongodb.sh

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Check if backup name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_name>"
    echo
    echo "Available backups:"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz$//' || echo "No backups found"
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

echo "=== MongoDB Restore Script ==="
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

# Check if MongoDB is running
echo "Checking MongoDB connection..."
if ! docker exec controlling-mongodb mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "Error: Cannot connect to MongoDB. Make sure Docker containers are running."
    echo "Run: docker compose up -d"
    exit 1
fi

echo "✓ MongoDB is running"

# Warning about data replacement
echo "⚠️  WARNING: This will replace all data in database '$MONGO_DATABASE'"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Drop existing database
echo "Dropping existing database '$MONGO_DATABASE'..."
docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').dropDatabase()"

# Copy backup data to container
echo "Copying backup data to container..."
docker cp "$RESTORE_PATH/$MONGO_DATABASE" controlling-mongodb:/tmp/restore

# Restore database using mongorestore
echo "Restoring database..."
docker exec controlling-mongodb mongorestore \
    --host localhost:27017 \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db "$MONGO_DATABASE" \
    /tmp/restore

# Restore users if they exist in backup
if [ -f "$RESTORE_PATH/users/users.json" ]; then
    echo "Restoring users..."
    # Note: User restoration might need manual intervention depending on the setup
    echo "Users backup found but automatic restoration not implemented."
    echo "Manual user restoration may be required using the file: $RESTORE_PATH/users/users.json"
fi

# Clean up temporary files in container
docker exec controlling-mongodb rm -rf /tmp/restore

# Verify restoration
echo "Verifying restoration..."
RESTORED_COUNT=$(docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').getCollectionNames().length")

DEALS_COUNT=$(docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('$MONGO_DATABASE').deals.countDocuments({})" 2>/dev/null || echo "0")

echo
echo "=== Restore Completed Successfully ==="
echo "Database: $MONGO_DATABASE"
echo "Collections restored: $RESTORED_COUNT"
echo "Deals documents: $DEALS_COUNT"
echo

# Clean up extracted backup directory
read -p "Remove extracted backup directory? (y/n): " cleanup
if [ "$cleanup" = "y" ]; then
    rm -rf "$RESTORE_PATH"
    echo "Cleanup completed."
fi

echo "Restore finished. Your MongoDB data has been restored from backup."
echo