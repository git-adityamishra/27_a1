from pymongo import MongoClient
from faker import Faker
from datetime import datetime, timezone

# 1. Establishing connection to local MongoDB server
client = MongoClient("mongodb://localhost:27017/")

# 2. Database and Collection Creation
db = client["stayspot"] 
collection = db["SearchSessions"]

fake = Faker()

# 3. Batching Setup
# We group data in memory, then push it to the database all at once.
batch_size = 10000
data_batch = []

print("Starting data generation... This might take a minute.")

for i in range(500000):
    # 4. GeoJSON Structure
    # Map data must explicitly declare a "type" (Point) and a "coordinates" array.
    document = {
        "location": {
            "type": "Point",
            "coordinates": [float(fake.longitude()), float(fake.latitude())]
        },
        "created_at": datetime.now(timezone.utc)
    }
    
    data_batch.append(document)
    
    # 5. Bulk Insertion
    # Once the batch hits 10,000 documents, insert them and reset the list.
    if len(data_batch) == batch_size:
        collection.insert_many(data_batch)
        data_batch = []

print("Successfully generated 500,000 geospatial records!")