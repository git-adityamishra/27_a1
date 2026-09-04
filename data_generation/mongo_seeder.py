from pymongo import MongoClient
from faker import Faker
from datetime import datetime, timezone
import random

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

# REVIEWS & AMENITIES GENERATION

def generate_property_amenities(num_properties=10000):
    print(f"Generating Amenities for {num_properties} properties...")
    amenities_collection = db["PropertyAmenities"]
    
    batch = []
    rules_options = ["No smoking", "No pets", "Quiet hours 10PM-8AM", "No parties", "Check-out by 11 AM"]
    accessibility_options = ["Wheelchair ramp", "Elevator", "Roll-in shower", "Step-free access", "Wide doorways"]
    
    for property_id in range(1, num_properties + 1):
        rules = random.sample(rules_options, 2)
        features = random.sample(accessibility_options, 2)
        
        amenity_document = {
            "property_id": property_id, # Integer matching Postgres IDs
            "house_rules": rules,
            "accessibility_features": features
        }
        batch.append(amenity_document)
        
        # Insert in batches of 5,000 to save memory
        if len(batch) >= 5000:
            amenities_collection.insert_many(batch)
            batch = []
            
    if batch:
        amenities_collection.insert_many(batch)
    print("Finished generating PropertyAmenities!")

def generate_property_reviews(num_reviews=50000, num_properties=10000, num_guests=50000):
    print(f"Generating {num_reviews} Reviews...")
    reviews_collection = db["PropertyReviews"]
    batch = []
    
    tags_options = ["Beachfront", "Downtown", "Quiet Neighborhood", "Near Transit", "Scenic View"]
    
    for _ in range(num_reviews):
        review_document = {
            "property_id": random.randint(1, num_properties), 
            "guest_id": random.randint(1, num_guests),        
            "rating": round(random.uniform(1.0, 5.0), 1),     
            "review_text": fake.paragraph(nb_sentences=3),    
            "location_tags": random.sample(tags_options, random.randint(1, 3)), 
            "timestamp": fake.date_time_this_year()           
        }
        batch.append(review_document)
        
        # Insert in batches of 5,000 to save memory
        if len(batch) >= 5000:
            reviews_collection.insert_many(batch)
            batch = []
            
    if batch:
        reviews_collection.insert_many(batch)
    print("Finished generating PropertyReviews!")


generate_property_amenities(num_properties=10000)
generate_property_reviews(num_reviews=50000, num_properties=10000, num_guests=50000)