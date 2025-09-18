# Controlling DB with Metabase and MongoDB

This setup provides a custom Metabase installation with MongoDB for financial data analysis.

## Quick Start

1. Copy the environment file:
   ```bash
   cp .env.example .env
   ```
   Then edit `.env` with your desired credentials.

2. Start the services:
   ```bash
   docker compose up -d
   ```

3. Access the web interfaces:
   - **Metabase**: http://localhost:3000
   - **MongoDB Express**: http://localhost:8081
4. MongoDB is available at: localhost:27017

## Environment Configuration

All sensitive data is stored in the `.env` file. You can customize:

- `MONGO_ROOT_USERNAME`: MongoDB admin username
- `MONGO_ROOT_PASSWORD`: MongoDB admin password  
- `MONGO_DATABASE`: MongoDB database name
- Metabase configuration variables

## MongoDB Connection Details

- **Host**: mongodb (within Docker network) or localhost:27017 (from host)
- **Database**: Value from `MONGO_DATABASE` (default: mongodb)
- **Username**: Value from `MONGO_ROOT_USERNAME` (default: admin)
- **Password**: Value from `MONGO_ROOT_PASSWORD` (default: password123)
- **Authentication Database**: admin

## Connecting Metabase to MongoDB

1. Open Metabase (http://localhost:3000)
2. Complete the initial setup
3. Add a database with these settings:
   - Database type: MongoDB
   - Host: mongodb
   - Port: 27017
   - Database name: mongodb (or your `MONGO_DATABASE` value)
   - Username: admin (or your `MONGO_ROOT_USERNAME` value)
   - Password: password123 (or your `MONGO_ROOT_PASSWORD` value)
   - Additional connection string options: `authSource=admin`

## Services

- **Metabase**: Port 3000 (custom build with Java 11)
- **MongoDB**: Port 27017 (with sample financial data)
- **MongoDB Express**: Port 8081 (web-based database admin interface)

## Volumes

- `mongodb_data`: Persistent MongoDB storage
- `metabase_data`: Persistent Metabase configuration

## Sample Data

The MongoDB instance includes sample transaction data in the `transactions` collection to get you started.