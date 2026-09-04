# StaySpot: Vacation Rental Database Architecture

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

PostgreSQL: An EXPLAIN ANALYZE confirms the materialized view successfully executes an Index Scan using idx_mv_property_summary_id with an execution time of 0.739 ms.

MongoDB: Raw output from .explain("executionStats") is documented in performance/mongo_execution_stats.json. It confirms that Workflow 3 successfully bypassed a collection scan, utilized the GEO_NEAR_2DSPHERE stage, and executed in 56 milliseconds.
