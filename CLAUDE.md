# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based financial data analysis platform combining Metabase (custom-built with Java 11) and MongoDB. The system is designed for IT agile controlling with financial transaction analysis capabilities.

## Common Commands

### Development Setup
```bash
# Copy environment configuration
cp .env.example .env

# Start all services in detached mode
docker compose up -d

# Stop all services
docker compose down

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f metabase
docker compose logs -f mongodb

# Rebuild Metabase container after changes
docker compose build metabase
docker compose up -d --no-deps metabase
```

### Database Operations
```bash
# Connect to MongoDB directly
docker exec -it controlling-mongodb mongosh -u admin -p --authenticationDatabase admin

# Access MongoDB from host
mongosh "mongodb://admin:password123@localhost:27017/financedb?authSource=admin"
```

## Architecture

### Services Structure
- **Metabase** (Port 3000): Custom Docker build using OpenJDK 11 with Metabase v0.47.7
- **MongoDB** (Port 27017): MongoDB 7.0 with authentication and sample financial data
- **MongoDB Express** (Port 8081): Web-based MongoDB admin interface for direct database access
- **Network**: `controlling-network` bridge network for service communication

### Data Flow
1. MongoDB stores financial transactions with sample data initialization
2. Metabase connects to MongoDB for data visualization and analysis
3. Sample data includes transactions with categories (groceries, income, transport)

### Environment Configuration
All sensitive configuration is managed through `.env` file:
- MongoDB credentials (`MONGO_ROOT_USERNAME`, `MONGO_ROOT_PASSWORD`)
- Database naming (`MONGO_DATABASE`)
- Metabase runtime settings (`MB_DB_TYPE`, `JAVA_TIMEZONE`, etc.)
- MongoDB Express authentication (`ME_CONFIG_BASICAUTH_USERNAME`, `ME_CONFIG_BASICAUTH_PASSWORD`)

### Persistent Storage
- `mongodb_data`: MongoDB database files
- `metabase_data`: Metabase application data and configurations

## MongoDB Connection Details
When configuring Metabase database connection:
- **Host**: `mongodb` (within Docker network)
- **Port**: `27017`
- **Authentication Database**: `admin`
- **Additional Connection String**: `authSource=admin`

## Web Interfaces
- **Metabase**: http://localhost:3000 - Data visualization and analytics
- **MongoDB Express**: http://localhost:8081 - Direct database administration

## Health Monitoring
Both services include health checks:
- Metabase: HTTP health endpoint (`/api/health`)
- MongoDB: Built-in container health monitoring