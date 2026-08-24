// Define the central coordinates for our search (e.g., targeting the Noida/Delhi tech hub area)
const targetCoordinates = [77.3231, 28.5703]; 

// Run the multi-stage aggregation pipeline
const trendingHotspots = db.SearchSessions.aggregate([
  {
    // STAGE 1: $geoNear (Must ALWAYS be the very first stage in the pipeline)
    // This calculates the distance of all points from our target coordinates.
    $geoNear: {
      near: { type: "Point", coordinates: targetCoordinates },
      distanceField: "distance_meters",
      maxDistance: 5000, // Strict 5km radius boundary[cite: 2]
      spherical: true
    }
  },
  {
    // STAGE 2: $project
    // We filter the output to only show the fields we actually want for our analytical clustering.
    $project: {
      _id: 0, 
      location: 1,
      distance_meters: { $round: ["$distance_meters", 2] }, // Rounds the math to 2 decimals
      created_at: 1
    }
  },
  {
    // STAGE 3: $sort
    // Orders the results so the closest search pins appear at the top.
    $sort: { distance_meters: 1 }
  },
  {
    // STAGE 4: $limit
    // Limits the output to the top 100 recent pings to prevent the terminal from overflowing.
    $limit: 100 
  }
]).toArray();

// Print the resulting JSON to the terminal
printjson(trendingHotspots);