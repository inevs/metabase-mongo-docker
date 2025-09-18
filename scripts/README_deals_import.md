# CSV Deals Import Script

## Description
This script imports deal data from the CSV file `data/deals-10118183-295.csv` into the MongoDB collection "deals".

## Usage

1. Make sure Docker services are running:
   ```bash
   docker compose up -d
   ```

2. Install Python dependencies:
   ```bash
   pip install -r scripts/requirements.txt
   ```

3. Run the import script:
   ```bash
   python scripts/import_deals_csv.py
   ```

## Configuration
The script uses environment variables that match your Docker setup:
- `MONGO_HOST`: Default 'localhost'
- `MONGO_PORT`: Default '27017'
- `MONGO_ROOT_USERNAME`: Default 'admin'
- `MONGO_ROOT_PASSWORD`: Default 'password123'
- `MONGO_DATABASE`: Default 'mongodb'

## Features
- Transforms German CSV headers to English field names
- Handles date parsing for various date formats
- Converts numeric fields appropriately
- Checks for existing deals by ID to avoid duplicates
- Creates useful indexes for query performance
- Provides progress feedback during import

## Data Structure
The script transforms CSV data into documents with fields like:
- `title`, `organization`, `value`, `status`
- `owner`, `contact_person`, `pipeline`
- `created_date`, `closed_date`, `won_date`
- `phase`, `probability`, `activities`
- And more...