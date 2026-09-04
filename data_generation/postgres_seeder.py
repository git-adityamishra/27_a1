import psycopg2
from psycopg2.extras import execute_values
import random
from datetime import datetime, timedelta
from faker import Faker

def connect_db():
    return psycopg2.connect(
        dbname="stayspot", 
        user="postgres", 
        host="localhost", 
        port="5432"
    )


def fetch_existing_ids(cursor, table_name):
    """Fetches all primary keys from a table so we can use them as valid Foreign Keys."""
    cursor.execute(f"SELECT id FROM {table_name};")
    # cursor.fetchall() returns a list of tuples: [(1,), (2,), (3,)]
    # We use a list comprehension to flatten it into: [1, 2, 3]
    return [row[0] for row in cursor.fetchall()]

def generate_and_insert_guests(cursor, num_guests):
    print(f"Generating {num_guests} fake guests...")

    fake = Faker()
    guest_data = []

    for _ in range(num_guests):
        name = fake.name()
        wallet_balance = round(random.uniform(500.0, 10000.0), 2)

        guest_data.append((name, wallet_balance))

    insert_query = """
        INSERT INTO guests (name, wallet_balance)
        VALUES %s
    """

    execute_values(cursor, insert_query, guest_data)

    print("Guests inserted successfully!")


def generate_and_insert_properties(cursor, num_properties):
    print(f"Generating {num_properties} fake properties...")

    fake = Faker()
    property_data = []

    # Cluster properties around a few real cities so geospatial
    # queries (Workflow 3 / $geoNear, 5km radius searches) return
    # meaningful, non-random results instead of points scattered
    # across the entire globe.
    cities = [
        (17.3850, 78.4867),   # Hyderabad
        (28.6139, 77.2090),   # Delhi
        (19.0760, 72.8777),   # Mumbai
        (12.9716, 77.5946),   # Bangalore
        (13.0827, 80.2707),   # Chennai
    ]

    for _ in range(num_properties):
        title = fake.sentence(nb_words=4)
        base_price = round(random.uniform(500.0, 10000.0), 2)

        base_lat, base_lng = random.choice(cities)
        # Small jitter (~5km) around the chosen city center
        latitude = round(base_lat + random.uniform(-0.05, 0.05), 6)
        longitude = round(base_lng + random.uniform(-0.05, 0.05), 6)

        property_data.append((title, base_price, latitude, longitude))

    insert_query = """
        INSERT INTO properties (title, base_price, latitude, longitude)
        VALUES %s
    """

    execute_values(cursor, insert_query, property_data)

    print("Properties inserted successfully!")

def generate_and_insert_bookings(cursor, guest_ids, property_ids, num_bookings):
    print(f"Generating {num_bookings} bookings...")
    booking_data = []
    
    # We use a set (like std::unordered_set) to track who is currently checked in
    # This ensures we don't violate your Day 3 partial index!
    active_checkins = set()
    
    statuses = ['COMPLETED', 'CONFIRMED', 'CHECKED_IN']
    
    for _ in range(num_bookings):
        guest_id = random.choice(guest_ids)
        property_id = random.choice(property_ids)
        total_cost = round(random.uniform(100.0, 2000.0), 2)
        
        # Determine status, respecting the partial index rule
        status = random.choice(statuses)
        if status == 'CHECKED_IN':
            if guest_id in active_checkins:
                status = 'CONFIRMED' # Fallback to avoid duplicate active stay
            else:
                active_checkins.add(guest_id)
                
        # Generate a random timestamp within the last year
        random_days_ago = random.randint(0, 365)
        created_at = datetime.now() - timedelta(days=random_days_ago)
        
        booking_data.append((guest_id, property_id, total_cost, status, created_at))

    insert_query = """
        INSERT INTO bookings (guest_id, property_id, total_cost, status, created_at) 
        VALUES %s
    """
    execute_values(cursor, insert_query, booking_data)
    print("Bookings inserted successfully!")

def generate_and_insert_audit_logs(cursor, guest_ids, num_logs):
    print(f"Generating {num_logs} historical wallet audit logs...")
    log_data = []
    batch_size = 10000  # Memory-safe chunking
    
    for _ in range(num_logs):
        guest_id = random.choice(guest_ids)
        amount_changed = round(random.uniform(10.0, 500.0), 2)
        action_type = random.choice(['CREDIT', 'DEBIT'])
        if action_type == 'DEBIT':
            amount_changed = -amount_changed
        balance_after = round(random.uniform(50.0, 5000.0), 2)
        
        random_days_ago = random.randint(0, 365)
        timestamp = datetime.now() - timedelta(days=random_days_ago)
        
        log_data.append((guest_id, amount_changed, action_type, balance_after, timestamp))
        
        # Push to Postgres when batch hits 10,000, then clear memory
        if len(log_data) >= batch_size:
            insert_query = """
                INSERT INTO wallet_audit_logs (guest_id, amount_changed, action_type, balance_after, timestamp) 
                VALUES %s
            """
            execute_values(cursor, insert_query, log_data)
            log_data = []  # Reset the list

    # Insert any remaining records
    if log_data:
        insert_query = """
            INSERT INTO wallet_audit_logs (guest_id, amount_changed, action_type, balance_after, timestamp) 
            VALUES %s
        """
        execute_values(cursor, insert_query, log_data)
        
    print("Audit logs inserted successfully in batches!")

def main():
    conn = None
    try:
        conn = connect_db()
        cursor = conn.cursor()

        # Step 1: Generate fake guests and properties
        generate_and_insert_guests(cursor, 100)
        generate_and_insert_properties(cursor, 50)

        # Step 1: "Coordinate" by fetching the real IDs generated by Member 1
        guest_ids = fetch_existing_ids(cursor, 'guests')
        property_ids = fetch_existing_ids(cursor, 'properties')

        if not guest_ids or not property_ids:
            print("Error: The guests or properties tables are empty. Member 1 must seed them first.")
            return

        # Step 2: Generate your assigned relational data
        # Rubric requires 100,000+ ledger/audit entries and 50,000+ bookings.
        generate_and_insert_bookings(cursor, guest_ids, property_ids, 50000)
        generate_and_insert_audit_logs(cursor, guest_ids, 100000)

        conn.commit()

    except Exception as e:
        print(f"Database error: {e}")
        if conn:
            conn.rollback()
    finally:
        if conn:
            cursor.close()
            conn.close()
            print("Database connection closed.")

if __name__ == "__main__":
    main()