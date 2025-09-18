#!/bin/bash

# MongoDB Backup Script for Docker Migration
# This script creates a backup of all MongoDB data including users and indexes

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mongodb_backup_$DATE"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

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

echo "=== MongoDB Backup Script ==="
echo "Date: $(date)"
echo "Database: $MONGO_DATABASE"
echo "Backup location: $BACKUP_PATH"
echo

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if MongoDB is running
echo "Checking MongoDB connection..."
if ! docker exec controlling-mongodb mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "Error: Cannot connect to MongoDB. Make sure Docker containers are running."
    echo "Run: docker compose up -d"
    exit 1
fi

echo "✓ MongoDB is running"

# Create database dump using mongodump inside the container
echo "Creating database dump..."
docker exec controlling-mongodb mongodump \
    --host localhost:27017 \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db "$MONGO_DATABASE" \
    --out /tmp/backup

# Copy backup from container to host
echo "Copying backup from container..."
docker cp controlling-mongodb:/tmp/backup "$BACKUP_PATH"

# Create users backup
echo "Creating users backup..."
mkdir -p "$BACKUP_PATH/users"
docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('admin').getUsers()" > "$BACKUP_PATH/users/users.json"

# Export environment configuration
echo "Backing up configuration..."
cp "$PROJECT_ROOT/.env" "$BACKUP_PATH/env_backup"
cp "$PROJECT_ROOT/docker-compose.yml" "$BACKUP_PATH/docker-compose_backup.yml"

# Create backup info file
cat > "$BACKUP_PATH/backup_info.txt" << EOF
MongoDB Backup Information
==========================
Created: $(date)
Database: $MONGO_DATABASE
MongoDB Version: $(docker exec controlling-mongodb mongod --version | head -1)
Host: $MONGO_HOST:$MONGO_PORT

Backup Contents:
- Database dump in '$MONGO_DATABASE/' directory
- Users backup in 'users/' directory
- Environment configuration in 'env_backup'
- Docker compose configuration in 'docker-compose_backup.yml'

Restore Instructions:
Run the restore script: ./scripts/restore_mongodb.sh $BACKUP_NAME
EOF

# Clean up temporary files in container
docker exec controlling-mongodb rm -rf /tmp/backup

# Create compressed archive
echo "Creating compressed archive..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Calculate and display backup size
BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)

echo
echo "=== Backup Completed Successfully ==="
echo "Backup file: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "Backup size: $BACKUP_SIZE"
echo "Backup contains:"
echo "  - Database: $MONGO_DATABASE"
echo "  - Users and permissions"
echo "  - Configuration files"
echo
echo "To restore on new server:"
echo "1. Copy the backup file to the new server"
echo "2. Extract: tar -xzf ${BACKUP_NAME}.tar.gz"
echo "3. Run: ./scripts/restore_mongodb.sh $BACKUP_NAME"
echo