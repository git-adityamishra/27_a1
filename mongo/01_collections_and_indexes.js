// 1. Connect to the correct database 
db = db.getSiblingDB('stayspot');

// 2. Create the Geospatial Index
// This tells MongoDB to treat the "location" field as spherical map coordinates.
db.SearchSessions.createIndex({ location: "2dsphere" });

// 3. Create the Time-To-Live Index
// The "1" means we are indexing the dates in ascending order. 
// "expireAfterSeconds: 7200" is the 2-hour deletion rule.
db.SearchSessions.createIndex({ created_at: 1 }, { expireAfterSeconds: 7200 });