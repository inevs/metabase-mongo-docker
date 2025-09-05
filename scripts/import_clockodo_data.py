#!/usr/bin/env python3
"""
Import Clockodo CSV data into MongoDB
"""

import argparse
import csv
import os
from datetime import datetime
from decimal import Decimal
from pymongo import MongoClient
import sys
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def parse_german_number(value):
    """Parse German number format (comma as decimal separator)"""
    if not value or value == '':
        return 0.0
    # Replace comma with dot for decimal conversion
    return float(value.replace(',', '.'))

def parse_month(month_str):
    """Parse YYYY-MM format to datetime"""
    try:
        return datetime.strptime(month_str, '%Y-%m')
    except ValueError:
        return None

def import_clockodo_data(csv_file_path, mongo_url, database_name, collection_name):
    """Import Clockodo CSV data into MongoDB"""
    
    # Connect to MongoDB
    try:
        client = MongoClient(mongo_url)
        db = client[database_name]
        collection = db[collection_name]
        print(f"Connected to MongoDB: {database_name}.{collection_name}")
    except Exception as e:
        print(f"Error connecting to MongoDB: {e}")
        return False
    
    # Read and import CSV data
    imported_count = 0
    try:
        with open(csv_file_path, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            
            # Process each row
            for row in reader:
                document = {
                    'kunde': row['Kunde'].strip('"'),
                    'projekt': row['Projekt'].strip('"'),
                    'monat': row['Monat'],
                    'monat_date': parse_month(row['Monat']),
                    'leistung': row['Leistung'].strip('"'),
                    'mitarbeiter': row['Mitarbeiter'].strip('"'),
                    'stunden': parse_german_number(row['Stunden']),
                    'umsatz_eur': parse_german_number(row['Umsatz in EUR'].strip('"')),
                    'imported_at': datetime.utcnow()
                }
                
                # Insert document
                collection.insert_one(document)
                imported_count += 1
                
                if imported_count % 100 == 0:
                    print(f"Imported {imported_count} records...")
        
        print(f"Successfully imported {imported_count} records")
        return True
        
    except Exception as e:
        print(f"Error importing data: {e}")
        return False
    finally:
        client.close()

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Import Clockodo CSV data into MongoDB',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/import_clockodo_data.py data/clockodo_2025-09-05_1042.csv
  python scripts/import_clockodo_data.py data/export.csv --collection my_data
  python scripts/import_clockodo_data.py /path/to/file.csv --database mydb --collection mycol
        """
    )
    
    parser.add_argument('csv_file', help='Path to the Clockodo CSV file')
    # Get MongoDB credentials from environment
    mongo_user = os.getenv('MONGO_ROOT_USERNAME')
    mongo_pass = os.getenv('MONGO_ROOT_PASSWORD')
    mongo_db = os.getenv('MONGO_DATABASE')
    
    # Check if required environment variables are set
    if not mongo_user or not mongo_pass or not mongo_db:
        print("Error: Required environment variables not found!")
        print("Please ensure .env file exists with:")
        print("  MONGO_ROOT_USERNAME=<username>")
        print("  MONGO_ROOT_PASSWORD=<password>")
        print("  MONGO_DATABASE=<database>")
        sys.exit(1)
    
    mongo_url = f'mongodb://{mongo_user}:{mongo_pass}@localhost:27017/{mongo_db}?authSource=admin'
    
    parser.add_argument('--database', '-d', default=mongo_db, 
                       help=f'MongoDB database name (default: {mongo_db})')
    parser.add_argument('--collection', '-c', default='clockodo_data',
                       help='MongoDB collection name (default: clockodo_data)')
    parser.add_argument('--mongo-url', default=mongo_url,
                       help='MongoDB connection URL (auto-generated from env vars)')
    
    args = parser.parse_args()
    
    # Configuration from arguments
    CSV_FILE = args.csv_file
    MONGO_URL = args.mongo_url
    DATABASE_NAME = args.database
    COLLECTION_NAME = args.collection
    
    # Convert relative paths to absolute paths
    if not os.path.isabs(CSV_FILE):
        CSV_FILE = os.path.join(os.getcwd(), CSV_FILE)
    
    # Check if CSV file exists
    if not os.path.exists(CSV_FILE):
        print(f"Error: CSV file not found: {CSV_FILE}")
        sys.exit(1)
    
    print("Starting Clockodo data import...")
    print(f"CSV file: {CSV_FILE}")
    print(f"MongoDB: {MONGO_URL}")
    print(f"Collection: {DATABASE_NAME}.{COLLECTION_NAME}")
    print("-" * 50)
    
    # Import data
    success = import_clockodo_data(CSV_FILE, MONGO_URL, DATABASE_NAME, COLLECTION_NAME)
    
    if success:
        print("\n✅ Import completed successfully!")
        print("\nYou can now:")
        print("1. View data in MongoDB Express: http://localhost:8081")
        print("2. Connect to the collection in Metabase for analysis")
        print(f"3. Query the data: db.{COLLECTION_NAME}.find().limit(5)")
    else:
        print("\n❌ Import failed!")
        sys.exit(1)

if __name__ == '__main__':
    main()