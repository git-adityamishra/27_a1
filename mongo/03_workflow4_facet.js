// Connect to the StaySpot database
// use stayspot;

// We use the aggregate() function to create our data assembly line
var pipeline = [
  {
    // $facet splits the data into three separate analytics pipelines
    $facet: {
      
      // 1. Rating Distributions: How many 1-star, 2-star, 3-star reviews?
      "ratingDistributions": [
        // Group all reviews by their rating number and add 1 to the count
        { $group: { _id: "$rating", count: { $sum: 1 } } },
        // Sort the results so 5-stars are at the top (-1 means descending)
        { $sort: { _id: -1 } } 
      ],

      // 2. Most Frequent Review Tags (FIXED: changed $tags to $location_tags)
      "frequentTags": [
        // $unwind takes an array and breaks it into separate rows 
        { $unwind: "$location_tags" }, 
        { $group: { _id: "$location_tags", count: { $sum: 1 } } },
        // Sort by the highest count
        { $sort: { count: -1 } }, 
        // Only show the top 10 most used tags
        { $limit: 10 } 
      ],

      // 3. Overall Average Property Rating
      "overallAverage": [
        // Grouping by "null" means "group absolutely everything together into one batch"
        { $group: { _id: null, averageRating: { $avg: "$rating" } } },
        // Format the output to round to 2 decimal places
        { $project: { _id: 0, averageRating: { $round: ["$averageRating", 2] } } }
      ]
    }
  }
];

// Execute the pipeline on the PropertyReviews collection and print the result nicely
print("--- StaySpot Review Analytics ---");
printjson(db.PropertyReviews.aggregate(pipeline).toArray());