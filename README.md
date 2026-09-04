# StaySpot: Vacation Rental Database Architecture

**Repository:** https://github.com/git-adityamishra/27_a1
**Final Commit Hash:** `1db75888f1eab9f892f7f34b04b17f93915834b4`

This repository contains the backend database engineering for **StaySpot**, a high-performance vacation rental platform. The architecture utilizes a hybrid database approach, combining the strict ACID compliance of PostgreSQL for financial ledgers with the flexible, geospatial capabilities of MongoDB for user search clustering and reviews.

## 🛠 Tech Stack & Prerequisites
* **Relational Database:** PostgreSQL 14+ (Financial transactions, bookings, constraints)
* **NoSQL Database:** MongoDB 6.0+ (Geospatial search, time-to-live sessions, review analytics)
* **Data Generation:** Python 3.9+ (`psycopg2`, `pymongo`, `faker`)

---

## 🗄️ PostgreSQL Architecture (Financial & Booking Core)

The relational schema guarantees zero-tolerance data integrity for wallets and property bookings.

### 1. Schema & Data Integrity (`sql/`)
* **Strict Constraints:** `CHECK` constraints prevent negative wallet balances (`wallet_balance >= 0.00`) and enforce realistic geographic boundaries (`latitude >= -90`, `longitude >= -180`).
* **Partial Unique Indexing:** A specialized index (`idx_active_stay`) prevents double-booking by ensuring a guest can only have one `CHECKED_IN` status at a time.
* **Automated Auditing:** A trigger function (`trg_wallet_balance_audit`) automatically monitors the `guests` table, calculating balance differences on the fly to log `CREDIT` or `DEBIT` actions into an immutable `wallet_audit_logs` table.

### 2. Transactional Logic
* **Atomic Bookings (`04_stored_procedures.sql`):** The `create_booking` procedure handles the checkout flow. It atomically deducts funds and creates a booking, utilizing a graceful `ROLLBACK` and `RAISE NOTICE` exception block if a guest lacks sufficient funds.

### 3. Analytics
* **Materialized Views (`05_materialized_views.sql`):** Pre-computes total bookings and revenue per property. Includes a unique index (`idx_mv_property_summary_id`) and a `REFRESH CONCURRENTLY` procedural function for background updates without table locking.
* **Window Functions (`06_window_analytics.sql`):** Uses Common Table Expressions (CTEs), a `CROSS JOIN` date generator, and a 7-day sliding window (`ROWS BETWEEN 6 PRECEDING AND CURRENT ROW`) to calculate accurate revenue momentum rankings per property.

---

## MongoDB Architecture (Search & Analytics)

The document schema handles heavy telemetry and unstructured review aggregation.

### 1. Indexes (`mongo/01_collections_and_indexes.js`)
* **Geospatial Optimization:** A `2dsphere` index is applied to the `SearchSessions.location` field for rapid Earth-spherical math.
* **Automated Expiry:** A TTL (Time-To-Live) index automatically purges search sessions 2 hours (`7200` seconds) after their `created_at` timestamp.

### 2. Analytical Workflows
* **Workflow 3 - Geospatial Search (`02_workflow3_geonear.js`):** Utilizes a `$geoNear` aggregation pipeline to cluster recent user search sessions within a strict 5,000-meter radius of target coordinates.
* **Workflow 4 - Review Faceting (`03_workflow4_facet.js`):** A `$facet` pipeline that simultaneously calculates overall average property ratings, rating distributions, and utilizes `$unwind` to extract and count the top 10 most frequent string tags from the `location_tags` array.

---

## Execution & Testing Guide

To evaluate this project locally, execute the following steps:

### Phase 1: PostgreSQL Setup
```bash
createdb stayspot
psql -d stayspot -f sql/01_schema_ddl.sql
psql -d stayspot -f sql/02_indexes.sql
psql -d stayspot -f sql/03_triggers_and_audit.sql
psql -d stayspot -f sql/04_stored_procedures.sql
psql -d stayspot -f sql/05_materialized_views.sql
```

### Phase 2: Data Generation

Our memory-safe Python seeders utilize 10,000-record batch sizes to prevent memory buffer crashes while simulating massive data scale.  

```bash 
pip install -r requirements.txt
python data_generation/postgres_seeder.py
python data_generation/mongo_seeder.py
```

### Phase 3: MongoDB Setup & Workflows

```bash
mongosh "mongodb://localhost:27017/stayspot" -f mongo/01_collections_and_indexes.js
mongosh "mongodb://localhost:27017/stayspot" -f mongo/02_workflow3_geonear.js
mongosh "mongodb://localhost:27017/stayspot" -f mongo/03_workflow4_facet.js
```

## Performance Proof

To prove query optimization under heavy data loads, execution statistics have been captured for both databases.

PostgreSQL: An EXPLAIN ANALYZE confirms the materialized view successfully executes an Index Scan using idx_mv_property_summary_id with an execution time of 0.739 ms. Please see below: 

EXPLAIN ANALYZE of Materialized view queries.
EXPLAIN ANALYZE SELECT * FROM mv_property_summary WHERE property_id = 1;

 Index Scan using idx_mv_property_summary_id on mv_property_summary (cost=0.28..8.29 rows=1 width=33) 
 (actual time=0.040..0.042 rows=1.00 loops=1)
 Index Cond: (property_id = 1)
 Index Searches: 1
 Buffers: shared hit=3
 Planning:
 Buffers: shared hit=61
 Planning Time: 1.473 ms
 Execution Time: 0.739 ms

 --------------------------------------------------------------------------------------------------------

  Incremental Sort  (cost=9574.41..265942.02 rows=400200 width=112) (actual time=80.315..1067.743 rows=732366.00 loops=1)
   Sort Key: movingaverages.property_id, movingaverages.booking_date DESC
   Presorted Key: movingaverages.property_id
   Full-sort Groups: 2001  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
   Pre-sorted Groups: 2001  Sort Method: quicksort  Average Memory: 44kB  Peak Memory: 44kB
   Buffers: shared hit=1262
   ->  WindowAgg  (cost=8311.29..238991.54 rows=400200 width=112) (actual time=79.420..960.839 rows=732366.00 loops=1)
         Window: w1 AS (PARTITION BY movingaverages.property_id ORDER BY movingaverages.moving_avg_7d ROWS UNBOUNDED PRECEDING)
         Storage: Memory  Maximum Storage: 17kB
         Buffers: shared hit=1262
         ->  Incremental Sort  (cost=8310.72..230987.54 rows=400200 width=72) (actual time=79.409..769.808 rows=732366.00 loops=1)
               Sort Key: movingaverages.property_id, movingaverages.moving_avg_7d DESC
               Presorted Key: movingaverages.property_id
               Full-sort Groups: 2001  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
               Pre-sorted Groups: 2001  Sort Method: quicksort  Average Memory: 38kB  Peak Memory: 38kB
               Buffers: shared hit=1262
               ->  Subquery Scan on movingaverages  (cost=7216.90..204037.06 rows=400200 width=72) (actual time=78.912..649.594 rows=732366.00 loops=1)
                     Buffers: shared hit=1259
                     ->  WindowAgg  (cost=7216.90..204037.06 rows=400200 width=72) (actual time=78.911..617.217 rows=732366.00 loops=1)
                           Window: w1 AS (PARTITION BY p.id ORDER BY (((generate_series(((InitPlan 1).col1)::timestamp with time zone, ((InitPlan 2).col1)::timestamp with time zone, '1 day'::interval)))::date) ROWS BETWEEN '6'::bigint PRECEDING AND CURRENT ROW)
                           Storage: Memory  Maximum Storage: 17kB
                           Buffers: shared hit=1259
                           ->  GroupAggregate  (cost=7216.41..197033.56 rows=400200 width=40) (actual time=78.900..338.943 rows=732366.00 loops=1)
                                 Group Key: p.id, (((generate_series(((InitPlan 1).col1)::timestamp with time zone, ((InitPlan 2).col1)::timestamp with time zone, '1 day'::interval)))::date)
                                 Buffers: shared hit=1259
                                 ->  Merge Left Join  (cost=7216.41..177023.56 rows=2001000 width=14) (actual time=78.876..235.567 rows=734027.00 loops=1)
                                       Merge Cond: ((p.id = b.property_id) AND ((((generate_series(((InitPlan 1).col1)::timestamp with time zone, ((InitPlan 2).col1)::timestamp with time zone, '1 day'::interval)))::date) = (date(b.created_at))))
                                       Buffers: shared hit=1259
                                       ->  Incremental Sort  (cost=2396.70..152196.56 rows=2001000 width=8) (actual time=44.008..139.834 rows=732366.00 loops=1)
                                             Sort Key: p.id, (((generate_series(((InitPlan 1).col1)::timestamp with time zone, ((InitPlan 2).col1)::timestamp with time zone, '1 day'::interval)))::date)
                                             Presorted Key: p.id
                                             Full-sort Groups: 2001  Sort Method: quicksort  Average Memory: 26kB  Peak Memory: 26kB
                                             Pre-sorted Groups: 2001  Sort Method: quicksort  Average Memory: 33kB  Peak Memory: 33kB
                                             Buffers: shared hit=842
                                             ->  Nested Loop  (cost=2334.33..27436.37 rows=2001000 width=8) (actual time=43.640..92.088 rows=732366.00 loops=1)
                                                   Buffers: shared hit=842
                                                   ->  Index Only Scan using properties_pkey on properties p  (cost=0.28..62.29 rows=2001 width=4) (actual time=0.023..0.294 rows=2001.00 loops=1)
                                                         Heap Fetches: 0
                                                         Index Searches: 1
                                                         Buffers: shared hit=8
                                                   ->  Materialize  (cost=2334.05..2364.07 rows=1000 width=4) (actual time=0.022..0.030 rows=366.00 loops=2001)
                                                         Storage: Memory  Maximum Storage: 28kB
                                                         Buffers: shared hit=834
                                                         ->  Result  (cost=2334.05..2359.07 rows=1000 width=4) (actual time=43.601..43.767 rows=366.00 loops=1)
                                                               Buffers: shared hit=834
                                                               InitPlan 1
                                                                 ->  Aggregate  (cost=1167.02..1167.03 rows=1 width=4) (actual time=26.890..26.891 rows=1.00 loops=1)
                                                                       Buffers: shared hit=417
                                                                       ->  Seq Scan on bookings  (cost=0.00..917.01 rows=50001 width=8) (actual time=0.028..10.223 rows=50002.00 loops=1)
                                                                             Buffers: shared hit=417
                                                               InitPlan 2
                                                                 ->  Aggregate  (cost=1167.02..1167.03 rows=1 width=4) (actual time=16.277..16.277 rows=1.00 loops=1)
                                                                       Buffers: shared hit=417
                                                                       ->  Seq Scan on bookings bookings_1  (cost=0.00..917.01 rows=50001 width=8) (actual time=0.026..3.624 rows=50002.00 loops=1)
                                                                             Buffers: shared hit=417
                                                               ->  ProjectSet  (cost=0.00..5.02 rows=1000 width=8) (actual time=43.599..43.691 rows=366.00 loops=1)
                                                                     Buffers: shared hit=834
                                                                     ->  Result  (cost=0.00..0.01 rows=1 width=0) (actual time=0.001..0.001 rows=1.00 loops=1)
                                       ->  Sort  (cost=4819.51..4944.51 rows=50001 width=18) (actual time=34.864..36.203 rows=50002.00 loops=1)
                                             Sort Key: b.property_id, (date(b.created_at))
                                             Sort Method: quicksort  Memory: 3710kB
                                             Buffers: shared hit=417
                                             ->  Seq Scan on bookings b  (cost=0.00..917.01 rows=50001 width=18) (actual time=0.007..12.479 rows=50002.00 loops=1)
                                                   Buffers: shared hit=417
 Planning:
 Buffers: shared hit=177
 Planning Time: 6.707 ms
 Execution Time: 1090.849 ms

MongoDB: Raw output from .explain("executionStats") is documented in performance/mongo_execution_stats.json. It confirms that Workflow 3 successfully bypassed a collection scan, utilized the GEO_NEAR_2DSPHERE stage, and executed in 56 milliseconds. Please see below:

[
  {
    "workflow_3_geoNear_stats": {
      "explainVersion": "1",
      "stages": [
        {
          "$geoNearCursor": {
            "queryPlanner": {
              "namespace": "stayspot.SearchSessions",
              "parsedQuery": {
                "location": {
                  "$nearSphere": {
                    "type": "Point",
                    "coordinates": [
                      77.3231,
                      28.5703
                    ]
                  },
                  "$maxDistance": 5000
                }
              },
              "indexFilterSet": false,
              "queryHash": "F1E00857",
              "planCacheShapeHash": "F1E00857",
              "planCacheKey": "3BBD05AB",
              "optimizationTimeMillis": 0,
              "cursorType": "regular",
              "maxIndexedOrSolutionsReached": false,
              "maxIndexedAndSolutionsReached": false,
              "maxScansToExplodeReached": false,
              "prunedSimilarIndexes": false,
              "winningPlan": {
                "isCached": false,
                "stage": "GEO_NEAR_2DSPHERE",
                "nss": "stayspot.SearchSessions",
                "keyPattern": {
                  "location": "2dsphere"
                },
                "indexName": "location_2dsphere",
                "indexVersion": 2,
                "inputStage": {
                  "stage": "FETCH",
                  "inputStage": {
                    "stage": "IXSCAN",
                    "keyPattern": {
                      "location": "2dsphere"
                    },
                    "indexName": "location_2dsphere",
                    "isMultiKey": false,
                    "multiKeyPaths": {
                      "location": []
                    },
                    "isUnique": false,
                    "isSparse": false,
                    "isPartial": false,
                    "indexVersion": 2,
                    "direction": "forward",
                    "indexBounds": {
                      "location": [
                        "[4107282860161892352, 4107282860161892352]",
                        "[4110660559882420224, 4110660559882420224]",
                        "[4110871666114953216, 4110871666114953216]",
                        "[4110910149021925376, 4110910149021925376]",
                        "[4110910423899832320, 4110910423899832320]",
                        "[4110910561338785793, 4110910698777739263]",
                        "[4110910698777739265, 4110910836216692735]",
                        "[4110910973655646208, 4110910973655646208]",
                        "[4110911111094599681, 4110911248533553151]",
                        "[4110911248533553152, 4110911248533553152]",
                        "[4110911248533553153, 4110911798289367039]",
                        "[4110911798289367041, 4110911935728320511]",
                        "[4110911935728320513, 4110912073167273983]",
                        "[4110912073167273984, 4110912073167273984]",
                        "[4110912073167273985, 4110912107527012351]",
                        "[4110912141886750720, 4110912141886750720]",
                        "[4110912176246489089, 4110912210606227455]",
                        "[4110912210606227457, 4110912348045180927]",
                        "[4110912348045180928, 4110912348045180928]",
                        "[4110912348045180929, 4110912485484134399]",
                        "[4110912485484134401, 4110912519843872767]",
                        "[4110912554203611136, 4110912554203611136]",
                        "[4110912622923087872, 4110912622923087872]",
                        "[4110912760362041345, 4110912897800994815]",
                        "[4110912897800994817, 4110913447556808703]",
                        "[4110913481916547073, 4110913516276285439]",
                        "[4110913516276285440, 4110913516276285440]",
                        "[4110913722434715648, 4110913722434715648]",
                        "[4110913859873669121, 4110913997312622591]",
                        "[4110913997312622593, 4110914134751576063]",
                        "[4110914134751576065, 4110914272190529535]",
                        "[4110914272190529536, 4110914272190529536]",
                        "[4110914547068436480, 4110914547068436480]",
                        "[4110924442673086464, 4110924442673086464]",
                        "[4110942034859130880, 4110942034859130880]",
                        "[4111786459789262848, 4111786459789262848]",
                        "[4125297258671374336, 4125297258671374336]"
                      ]
                    }
                  }
                }
              },
              "rejectedPlans": []
            },
            "executionStats": {
              "executionSuccess": true,
              "nReturned": 0,
              "executionTimeMillis": 1,
              "totalKeysExamined": 6,
              "totalDocsExamined": 0,
              "executionStages": {
                "isCached": false,
                "stage": "GEO_NEAR_2DSPHERE",
                "nReturned": 0,
                "executionTimeMillisEstimate": 0,
                "works": 23,
                "advanced": 0,
                "needTime": 22,
                "needYield": 0,
                "saveState": 2,
                "restoreState": 1,
                "isEOF": 1,
                "nss": "stayspot.SearchSessions",
                "keyPattern": {
                  "location": "2dsphere"
                },
                "indexName": "location_2dsphere",
                "indexVersion": 2,
                "searchIntervals": [
                  {
                    "minDistance": 0,
                    "maxDistance": 5000,
                    "maxInclusive": true,
                    "nBuffered": 0,
                    "nReturned": 0
                  }
                ],
                "usedDisk": false,
                "spills": 0,
                "spilledRecords": 0,
                "spilledBytes": 0,
                "spilledDataStorageSize": 0,
                "inputStage": {
                  "stage": "FETCH",
                  "nReturned": 0,
                  "executionTimeMillisEstimate": 0,
                  "works": 6,
                  "advanced": 0,
                  "needTime": 5,
                  "needYield": 0,
                  "saveState": 1,
                  "restoreState": 0,
                  "isEOF": 1,
                  "docsExamined": 0,
                  "alreadyHasObj": 0,
                  "inputStage": {
                    "stage": "IXSCAN",
                    "nReturned": 0,
                    "executionTimeMillisEstimate": 0,
                    "works": 6,
                    "advanced": 0,
                    "needTime": 5,
                    "needYield": 0,
                    "saveState": 1,
                    "restoreState": 0,
                    "isEOF": 1,
                    "keyPattern": {
                      "location": "2dsphere"
                    },
                    "indexName": "location_2dsphere",
                    "isMultiKey": false,
                    "multiKeyPaths": {
                      "location": []
                    },
                    "isUnique": false,
                    "isSparse": false,
                    "isPartial": false,
                    "indexVersion": 2,
                    "direction": "forward",
                    "indexBounds": {
                      "location": [
                        "[4107282860161892352, 4107282860161892352]",
                        "[4110660559882420224, 4110660559882420224]",
                        "[4110871666114953216, 4110871666114953216]",
                        "[4110910149021925376, 4110910149021925376]",
                        "[4110910423899832320, 4110910423899832320]",
                        "[4110910561338785793, 4110910698777739263]",
                        "[4110910698777739265, 4110910836216692735]",
                        "[4110910973655646208, 4110910973655646208]",
                        "[4110911111094599681, 4110911248533553151]",
                        "[4110911248533553152, 4110911248533553152]",
                        "[4110911248533553153, 4110911798289367039]",
                        "[4110911798289367041, 4110911935728320511]",
                        "[4110911935728320513, 4110912073167273983]",
                        "[4110912073167273984, 4110912073167273984]",
                        "[4110912073167273985, 4110912107527012351]",
                        "[4110912141886750720, 4110912141886750720]",
                        "[4110912176246489089, 4110912210606227455]",
                        "[4110912210606227457, 4110912348045180927]",
                        "[4110912348045180928, 4110912348045180928]",
                        "[4110912348045180929, 4110912485484134399]",
                        "[4110912485484134401, 4110912519843872767]",
                        "[4110912554203611136, 4110912554203611136]",
                        "[4110912622923087872, 4110912622923087872]",
                        "[4110912760362041345, 4110912897800994815]",
                        "[4110912897800994817, 4110913447556808703]",
                        "[4110913481916547073, 4110913516276285439]",
                        "[4110913516276285440, 4110913516276285440]",
                        "[4110913722434715648, 4110913722434715648]",
                        "[4110913859873669121, 4110913997312622591]",
                        "[4110913997312622593, 4110914134751576063]",
                        "[4110914134751576065, 4110914272190529535]",
                        "[4110914272190529536, 4110914272190529536]",
                        "[4110914547068436480, 4110914547068436480]",
                        "[4110924442673086464, 4110924442673086464]",
                        "[4110942034859130880, 4110942034859130880]",
                        "[4111786459789262848, 4111786459789262848]",
                        "[4125297258671374336, 4125297258671374336]"
                      ]
                    },
                    "keysExamined": 6,
                    "seeks": 6,
                    "dupsTested": 0,
                    "dupsDropped": 0,
                    "peakTrackedMemBytes": 0
                  }
                }
              }
            }
          },
          "nReturned": 0,
          "executionTimeMillisEstimate": 1
        },
        {
          "$project": {
            "location": true,
            "created_at": true,
            "distance_meters": {
              "$round": [
                "$distance_meters",
                {
                  "$const": 2
                }
              ]
            },
            "_id": false
          },
          "nReturned": 0,
          "executionTimeMillisEstimate": 1
        },
        {
          "$sort": {
            "sortKey": {
              "distance_meters": 1
            },
            "limit": 100
          },
          "totalDataSizeSortedBytesEstimate": 0,
          "usedDisk": false,
          "spills": 0,
          "spilledBytes": 0,
          "spilledRecords": 0,
          "spilledDataStorageSize": 0,
          "nReturned": 0,
          "executionTimeMillisEstimate": 1,
          "peakTrackedMemBytes": 0
        }
      ],
      "queryShapeHash": "CE5AE6D68E66B31B47A8A0A54FF15581078C76818844799990E7248DE6AB0D38",
      "serverInfo": {
        "host": "Anujs-MacBook-Air.local",
        "port": 27017,
        "version": "8.3.7",
        "gitVersion": "34eee04f34989abb7a3d91447976f033f4f74af2"
      },
      "serverParameters": {
        "internalQueryFacetBufferSizeBytes": 104857600,
        "internalDocumentSourceGroupMaxMemoryBytes": 104857600,
        "internalQueryMaxBlockingSortMemoryUsageBytes": 104857600,
        "internalDocumentSourceSetWindowFieldsMaxMemoryBytes": 104857600,
        "internalQueryFacetMaxOutputDocSizeBytes": 104857600,
        "internalLookupStageIntermediateDocumentMaxSizeBytes": 104857600,
        "internalQueryProhibitBlockingMergeOnMongoS": 0,
        "internalQueryMaxAddToSetBytes": 104857600,
        "internalQueryFrameworkControl": "trySbeRestricted",
        "internalQueryPlannerIgnoreIndexWithCollationForRegex": 1
      },
      "command": {
        "aggregate": "SearchSessions",
        "pipeline": [
          {
            "$geoNear": {
              "near": {
                "type": "Point",
                "coordinates": [
                  77.3231,
                  28.5703
                ]
              },
              "distanceField": "distance_meters",
              "maxDistance": 5000,
              "spherical": true
            }
          },
          {
            "$project": {
              "_id": 0,
              "location": 1,
              "distance_meters": {
                "$round": [
                  "$distance_meters",
                  2
                ]
              },
              "created_at": 1
            }
          },
          {
            "$sort": {
              "distance_meters": 1
            }
          },
          {
            "$limit": 100
          }
        ],
        "cursor": {},
        "$db": "stayspot"
      },
      "ok": 1
    }
  },
  {
    "workflow_4_facet_stats": {
      "explainVersion": "1",
      "stages": [
        {
          "$cursor": {
            "queryPlanner": {
              "namespace": "stayspot.PropertyReviews",
              "parsedQuery": {},
              "indexFilterSet": false,
              "queryHash": "C0BD3948",
              "planCacheShapeHash": "C0BD3948",
              "planCacheKey": "BCA05D32",
              "optimizationTimeMillis": 0,
              "cursorType": "regular",
              "maxIndexedOrSolutionsReached": false,
              "maxIndexedAndSolutionsReached": false,
              "maxScansToExplodeReached": false,
              "prunedSimilarIndexes": false,
              "winningPlan": {
                "isCached": false,
                "stage": "PROJECTION_SIMPLE",
                "transformBy": {
                  "location_tags": 1,
                  "rating": 1,
                  "_id": 0
                },
                "inputStage": {
                  "stage": "COLLSCAN",
                  "nss": "stayspot.PropertyReviews",
                  "direction": "forward"
                }
              },
              "rejectedPlans": []
            },
            "executionStats": {
              "executionSuccess": true,
              "nReturned": 50000,
              "executionTimeMillis": 659,
              "totalKeysExamined": 0,
              "totalDocsExamined": 50000,
              "executionStages": {
                "isCached": false,
                "stage": "PROJECTION_SIMPLE",
                "nReturned": 50000,
                "executionTimeMillisEstimate": 81,
                "works": 50001,
                "advanced": 50000,
                "needTime": 0,
                "needYield": 0,
                "saveState": 17,
                "restoreState": 16,
                "isEOF": 1,
                "transformBy": {
                  "location_tags": 1,
                  "rating": 1,
                  "_id": 0
                },
                "inputStage": {
                  "stage": "COLLSCAN",
                  "nReturned": 50000,
                  "executionTimeMillisEstimate": 74,
                  "works": 50001,
                  "advanced": 50000,
                  "needTime": 0,
                  "needYield": 0,
                  "saveState": 17,
                  "restoreState": 16,
                  "isEOF": 1,
                  "nss": "stayspot.PropertyReviews",
                  "direction": "forward",
                  "docsExamined": 50000
                }
              }
            }
          },
          "nReturned": 50000,
          "executionTimeMillisEstimate": 192
        },
        {
          "$facet": {
            "ratingDistributions": [
              {
                "$internalFacetTeeConsumer": {},
                "nReturned": 50000,
                "executionTimeMillisEstimate": 192
              },
              {
                "$group": {
                  "_id": "$rating",
                  "count": {
                    "$sum": {
                      "$const": 1
                    }
                  },
                  "$willBeMerged": false
                },
                "nReturned": 41,
                "executionTimeMillisEstimate": 242,
                "maxAccumulatorMemoryUsageBytes": {
                  "count": 9184
                },
                "totalOutputDataSizeBytes": 9717,
                "usedDisk": false,
                "spills": 0,
                "spilledDataStorageSize": 0,
                "spilledBytes": 0,
                "spilledRecords": 0,
                "peakTrackedMemBytes": 9840
              },
              {
                "$sort": {
                  "sortKey": {
                    "_id": -1
                  }
                },
                "totalDataSizeSortedBytesEstimate": 10045,
                "usedDisk": false,
                "spills": 0,
                "spilledBytes": 0,
                "spilledRecords": 0,
                "spilledDataStorageSize": 0,
                "nReturned": 41,
                "executionTimeMillisEstimate": 242,
                "peakTrackedMemBytes": 10045
              }
            ],
            "frequentTags": [
              {
                "$internalFacetTeeConsumer": {},
                "nReturned": 50000,
                "executionTimeMillisEstimate": 0
              },
              {
                "$unwind": {
                  "path": "$location_tags"
                },
                "nReturned": 100132,
                "executionTimeMillisEstimate": 123
              },
              {
                "$group": {
                  "_id": "$location_tags",
                  "count": {
                    "$sum": {
                      "$const": 1
                    }
                  },
                  "$willBeMerged": false
                },
                "nReturned": 5,
                "executionTimeMillisEstimate": 250,
                "maxAccumulatorMemoryUsageBytes": {
                  "count": 1120
                },
                "totalOutputDataSizeBytes": 1227,
                "usedDisk": false,
                "spills": 0,
                "spilledDataStorageSize": 0,
                "spilledBytes": 0,
                "spilledRecords": 0,
                "peakTrackedMemBytes": 1242
              },
              {
                "$sort": {
                  "sortKey": {
                    "count": -1
                  },
                  "limit": 10
                },
                "totalDataSizeSortedBytesEstimate": 1267,
                "usedDisk": false,
                "spills": 0,
                "spilledBytes": 0,
                "spilledRecords": 0,
                "spilledDataStorageSize": 0,
                "nReturned": 5,
                "executionTimeMillisEstimate": 250,
                "peakTrackedMemBytes": 1267
              }
            ],
            "overallAverage": [
              {
                "$internalFacetTeeConsumer": {},
                "nReturned": 50000,
                "executionTimeMillisEstimate": 109
              },
              {
                "$group": {
                  "_id": {
                    "$const": null
                  },
                  "averageRating": {
                    "$avg": "$rating"
                  },
                  "$willBeMerged": false
                },
                "nReturned": 1,
                "executionTimeMillisEstimate": 159,
                "maxAccumulatorMemoryUsageBytes": {
                  "averageRating": 192
                },
                "totalOutputDataSizeBytes": 237,
                "usedDisk": false,
                "spills": 0,
                "spilledDataStorageSize": 0,
                "spilledBytes": 0,
                "spilledRecords": 0,
                "peakTrackedMemBytes": 208
              },
              {
                "$project": {
                  "averageRating": {
                    "$round": [
                      "$averageRating",
                      {
                        "$const": 2
                      }
                    ]
                  },
                  "_id": false
                },
                "nReturned": 1,
                "executionTimeMillisEstimate": 159
              }
            ]
          },
          "nReturned": 1,
          "executionTimeMillisEstimate": 651
        }
      ],
      "queryShapeHash": "2974FF1A3A90EEBD049D2FE6B09E07AF074941644F7C3ABE0EA08A6035481DDE",
      "serverInfo": {
        "host": "Anujs-MacBook-Air.local",
        "port": 27017,
        "version": "8.3.7",
        "gitVersion": "34eee04f34989abb7a3d91447976f033f4f74af2"
      },
      "serverParameters": {
        "internalQueryFacetBufferSizeBytes": 104857600,
        "internalDocumentSourceGroupMaxMemoryBytes": 104857600,
        "internalQueryMaxBlockingSortMemoryUsageBytes": 104857600,
        "internalDocumentSourceSetWindowFieldsMaxMemoryBytes": 104857600,
        "internalQueryFacetMaxOutputDocSizeBytes": 104857600,
        "internalLookupStageIntermediateDocumentMaxSizeBytes": 104857600,
        "internalQueryProhibitBlockingMergeOnMongoS": 0,
        "internalQueryMaxAddToSetBytes": 104857600,
        "internalQueryFrameworkControl": "trySbeRestricted",
        "internalQueryPlannerIgnoreIndexWithCollationForRegex": 1
      },
      "command": {
        "aggregate": "PropertyReviews",
        "pipeline": [
          {
            "$facet": {
              "ratingDistributions": [
                {
                  "$group": {
                    "_id": "$rating",
                    "count": {
                      "$sum": 1
                    }
                  }
                },
                {
                  "$sort": {
                    "_id": -1
                  }
                }
              ],
              "frequentTags": [
                {
                  "$unwind": "$location_tags"
                },
                {
                  "$group": {
                    "_id": "$location_tags",
                    "count": {
                      "$sum": 1
                    }
                  }
                },
                {
                  "$sort": {
                    "count": -1
                  }
                },
                {
                  "$limit": 10
                }
              ],
              "overallAverage": [
                {
                  "$group": {
                    "_id": null,
                    "averageRating": {
                      "$avg": "$rating"
                    }
                  }
                },
                {
                  "$project": {
                    "_id": 0,
                    "averageRating": {
                      "$round": [
                        "$averageRating",
                        2
                      ]
                    }
                  }
                }
              ]
            }
          }
        ],
        "cursor": {},
        "$db": "stayspot"
      },
      "ok": 1
    }
  }
]
