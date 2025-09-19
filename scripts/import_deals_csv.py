#!/usr/bin/env python3
"""
Script to import CSV deals data into MongoDB
"""

import csv
import os
import argparse
from datetime import datetime
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
import sys

def parse_date(date_str):
    """Parse date string in format 'YYYY-MM-DD HH:MM:SS' or 'YYYY-MM-DD'"""
    if not date_str or date_str.strip() == '':
        return None

    try:
        # Try full datetime format first
        if ' ' in date_str:
            return datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
        else:
            return datetime.strptime(date_str, '%Y-%m-%d')
    except ValueError:
        print(f"Warning: Could not parse date '{date_str}'")
        return None

def parse_number(value_str):
    """Parse numeric string, return None if empty or invalid"""
    if not value_str or value_str.strip() == '':
        return None
    try:
        return float(value_str)
    except ValueError:
        print(f"Warning: Could not parse number '{value_str}'")
        return None

def transform_deal_row(row):
    """Transform CSV row to MongoDB document"""
    return {
        'title': row['Deal - Titel'],
        'organization': row['Deal - Organisation'],
        'value': parse_number(row['Deal - Wert']),
        'status': row['Deal - Status'],
        'loss_reason': row['Deal - Verlustgrund'],
        'owner': row['Deal - Besitzer'],
        'created_date': parse_date(row['Deal - Deal erstellt']),
        'lost_date': parse_date(row['Deal - Datum des verlorenen Deals']),
        'phase': row['Deal - Phase'],
        'pending_activities': parse_number(row['Deal - Zu erledigende Aktivitäten']),
        'contact_person': row['Deal - Kontaktperson'],
        'closed_date': parse_date(row['Deal - Deal abgeschlossen am']),
        'completed_activities': parse_number(row['Deal - Erledigte Aktivitäten']),
        'email_count': parse_number(row['Deal - Anzahl E-Mail-Nachrichten']),
        'deal_id': row['Deal - ID'],
        'label': row['Deal - Label'],
        'last_activity_date': parse_date(row['Deal - Datum der letzten Aktivität']),
        'last_email_received': parse_date(row['Deal - Letzte E-Mail erhalten']),
        'last_email_sent': parse_date(row['Deal - Letzte E-Mail gesendet']),
        'last_phase_change': parse_date(row['Deal - Letzte Phasenänderung']),
        'next_activity_date': parse_date(row['Deal - Datum nächste Aktivität']),
        'probability': parse_number(row['Deal - Wahrscheinlichkeit']),
        'total_activities': parse_number(row['Deal - Gesamtzahl der Aktivitäten']),
        'last_update': parse_date(row['Deal - Zeit der Aktualisierung']),
        'visibility': row['Deal - Sichtbar für'],
        'weighted_value': parse_number(row['Deal - Gewichteter Wert']),
        'pipeline': row['Deal - Pipeline'],
        'won_date': parse_date(row['Deal - Datum des gewonnenen Deals']),
        'imported_at': datetime.now()
    }

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Import CSV deals data into MongoDB')
    parser.add_argument('csv_file', help='Path to the CSV file to import')
    args = parser.parse_args()

    # MongoDB connection settings from environment or defaults
    mongo_host = os.getenv('MONGO_HOST', 'localhost')
    mongo_port = int(os.getenv('MONGO_PORT', '27017'))
    mongo_username = os.getenv('MONGO_ROOT_USERNAME', 'admin')
    mongo_password = os.getenv('MONGO_ROOT_PASSWORD', 'password123')
    mongo_database = os.getenv('MONGO_DATABASE', 'mongodb')

    # CSV file path from argument
    csv_file_path = args.csv_file

    if not os.path.exists(csv_file_path):
        print(f"Error: CSV file not found at {csv_file_path}")
        sys.exit(1)

    try:
        # Connect to MongoDB
        connection_string = f"mongodb://{mongo_username}:{mongo_password}@{mongo_host}:{mongo_port}/{mongo_database}?authSource=admin"
        client = MongoClient(connection_string)

        # Test connection
        client.admin.command('ismaster')
        print("Connected to MongoDB successfully")

        # Get database and collection
        db = client[mongo_database]
        deals_collection = db.deals

        # Read and import CSV data
        imported_count = 0
        skipped_count = 0

        print(f"Reading CSV file: {csv_file_path}")

        with open(csv_file_path, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)

            # Check if the collection should be cleared first
            existing_count = deals_collection.count_documents({})
            if existing_count > 0:
                response = input(f"Collection 'deals' already contains {existing_count} documents. Clear it first? (y/N): ")
                if response.lower() == 'y':
                    deals_collection.delete_many({})
                    print("Collection cleared")

            for row in reader:
                try:
                    # Transform row to document
                    deal_doc = transform_deal_row(row)

                    # Check if deal already exists (by deal_id)
                    if deal_doc['deal_id']:
                        existing = deals_collection.find_one({'deal_id': deal_doc['deal_id']})
                        if existing:
                            print(f"Deal with ID {deal_doc['deal_id']} already exists, skipping")
                            skipped_count += 1
                            continue

                    # Insert document
                    deals_collection.insert_one(deal_doc)
                    imported_count += 1

                    if imported_count % 10 == 0:
                        print(f"Imported {imported_count} deals...")

                except Exception as e:
                    print(f"Error processing row: {e}")
                    continue

        print(f"\nImport completed!")
        print(f"Imported: {imported_count} deals")
        print(f"Skipped: {skipped_count} deals")
        print(f"Total documents in collection: {deals_collection.count_documents({})}")

        # Create indexes for better performance
        print("\nCreating indexes...")
        deals_collection.create_index("deal_id", unique=True, sparse=True)
        deals_collection.create_index("status")
        deals_collection.create_index("owner")
        deals_collection.create_index("organization")
        deals_collection.create_index("created_date")
        print("Indexes created")

    except ConnectionFailure:
        print("Error: Could not connect to MongoDB")
        print("Make sure MongoDB is running and credentials are correct")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        if 'client' in locals():
            client.close()

if __name__ == "__main__":
    main()