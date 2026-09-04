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

MongoDB: Raw output from .explain("executionStats") is documented in performance/mongo_execution_stats.json. It confirms that Workflow 3 successfully bypassed a collection scan, utilized the GEO_NEAR_2DSPHERE stage, and executed in 56 milliseconds.
