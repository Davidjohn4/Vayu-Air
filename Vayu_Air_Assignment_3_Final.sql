

/*
1.
State the grain of the sales fact you will build, written as a comment, and
classify every candidate column from bronze_bookings (joined to its flight) as a dimension key or a measure.
Add one sentence naming which measures are additive and giving one example of a value that would not be additive. 
Acceptance criteria: a clear one-row grain statement; 
a correct split of columns into dimension keys versus measures; one additive-versus-non-additive note.
*/
-- Grain:
-- One row per ticket sold: one booking record for one passenger on one flight.

-- Column classification:
-- booking_id          = Degenerate dimension (row identifier, no dim table)
-- passenger_id        = Dimension key (dim_passenger)
-- flight_id           = Dimension key (dim_flight)
-- booking_date        = Dimension key (dim_date, role: booking)
-- travel_date         = Dimension key (dim_date, role: travel)
-- fare_class          = Dimension attribute (small dim / junk dim)
-- booking_status      = Dimension attribute (small dim / junk dim)
-- flight_number       = Attribute of dim_flight (via flight_id)
-- origin_airport_code = Dimension key (dim_airport, role: origin)
-- dest_airport_code   = Dimension key (dim_airport, role: destination)
-- aircraft_code       = Dimension key (dim_aircraft)
-- flight_date         = Same as travel_date; use one date key
-- fare_amount         = Measure
-- tax_amount          = Measure
-- miles_earned        = Measure

-- Additive: fare_amount, tax_amount and miles_earned can be summed across
-- any dimension. A non-additive value is average fare (or any ratio):
-- summing or averaging averages is wrong, so recompute it as SUM(fare)/COUNT(*).


/*
2.
Create a dw schema and write the star schema DDL: a central
FactTicketSales at your declared grain plus the dimensions it needs (date, passenger, flight, airport, aircraft).
Use surrogate keys on the dimensions and foreign keys on the fact, and keep only additive measures on the fact.
Acceptance criteria: fact at the declared grain with surrogate-key foreign keys;
each dimension has a surrogate primary key and keeps its business key.
*/

CREATE SCHEMA dw;
GO

CREATE TABLE dw.DimPassenger
(
    passenger_key       INT IDENTITY(1,1) PRIMARY KEY,   -- surrogate key
    passenger_id        VARCHAR(20) NOT NULL,            -- business key
    passenger_name      VARCHAR(50),
    home_airport_code   VARCHAR(3),
    frequent_flyer_tier VARCHAR(20),
    signup_date         DATE,
    effective_from      DATE NOT NULL DEFAULT '1900-01-01',
    effective_to        DATE NULL,
    is_current          BIT  NOT NULL DEFAULT 1
);

CREATE TABLE dw.DimDate
(
    date_key            INT PRIMARY KEY,                 -- e.g. 20261119
    calendar_date       DATE NOT NULL UNIQUE,
    calendar_month      INT,
    calendar_month_name VARCHAR(20),
    calendar_year       INT,
    calendar_quarter    VARCHAR(20)
);

CREATE TABLE dw.DimFlight
(
    flight_key    INT IDENTITY(1,1) PRIMARY KEY,
    flight_id     INT NOT NULL UNIQUE,                   -- business key
    flight_number VARCHAR(20),
    flight_date   DATE
);

CREATE TABLE dw.DimAirport
(
    airport_key  INT IDENTITY(1,1) PRIMARY KEY,
    airport_code VARCHAR(3) NOT NULL UNIQUE,
    airport_name VARCHAR(100),
    city         VARCHAR(50),
    country      VARCHAR(50),
    region       VARCHAR(50)
);

CREATE TABLE dw.DimAircraft
(
    aircraft_key  INT IDENTITY(1,1) PRIMARY KEY,
    aircraft_code VARCHAR(10) NOT NULL UNIQUE,
    model         VARCHAR(50),
    manufacturer  VARCHAR(50),
    seat_capacity INT
);

CREATE TABLE dw.FactTicketSales
(
    booking_id         INT NOT NULL PRIMARY KEY,         -- degenerate dimension
    passenger_key      INT NOT NULL REFERENCES dw.DimPassenger(passenger_key),
    flight_key         INT NOT NULL REFERENCES dw.DimFlight(flight_key),
    booking_date_key   INT NOT NULL REFERENCES dw.DimDate(date_key),
    travel_date_key    INT NOT NULL REFERENCES dw.DimDate(date_key),
    origin_airport_key INT NOT NULL REFERENCES dw.DimAirport(airport_key),
    dest_airport_key   INT NOT NULL REFERENCES dw.DimAirport(airport_key),
    aircraft_key       INT NOT NULL REFERENCES dw.DimAircraft(aircraft_key),
    fare_class         VARCHAR(25),
    booking_status     VARCHAR(20),
    fare_amount        DECIMAL(12,2),
    tax_amount         DECIMAL(12,2),
    miles_earned       INT
);

/*
3.
Load the dimensions and the fact from the bronze_* tables, assigning the
surrogate keys. Build a DimDate with a yyyymmdd integer DateKey. 
Populate the fact by joining bookings to the dimensions on their business keys. Acceptance criteria: 
dimensions and fact are populated; 
the fact row count matches bronze_bookings; every fact row resolves to all of its dimensions.
*/

-- DimDate: continuous calendar covering every date used
DECLARE @min DATE, @max DATE;
SELECT @min = MIN(d), @max = MAX(d)
FROM (
    SELECT booking_date AS d FROM bronze_bookings
    UNION ALL SELECT travel_date FROM bronze_bookings
    UNION ALL SELECT flight_date FROM bronze_flights
) x;

WITH cal AS (
    SELECT @min AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM cal WHERE d < @max
)
INSERT INTO dw.DimDate (date_key, calendar_date, calendar_month,
                        calendar_month_name, calendar_year, calendar_quarter)
SELECT CONVERT(INT, CONVERT(CHAR(8), d, 112)),
       d, MONTH(d), DATENAME(MONTH, d), YEAR(d),
       CONCAT('Q', DATEPART(QUARTER, d))
FROM cal
OPTION (MAXRECURSION 0);

-- Dimensions
INSERT INTO dw.DimPassenger (passenger_id, passenger_name, home_airport_code,
                             frequent_flyer_tier, signup_date)
SELECT passenger_id, passenger_name, home_airport_code,
       frequent_flyer_tier, signup_date
FROM bronze_passengers;

INSERT INTO dw.DimAirport (airport_code, airport_name, city, country, region)
SELECT airport_code, airport_name, city, country, region
FROM bronze_airports;

INSERT INTO dw.DimAircraft (aircraft_code, model, manufacturer, seat_capacity)
SELECT aircraft_code, model, manufacturer, seat_capacity
FROM bronze_aircraft;

INSERT INTO dw.DimFlight (flight_id, flight_number, flight_date)
SELECT flight_id, flight_number, flight_date
FROM bronze_flights;

-- Fact
INSERT INTO dw.FactTicketSales
(booking_id, passenger_key, flight_key, booking_date_key, travel_date_key,
 origin_airport_key, dest_airport_key, aircraft_key,
 fare_class, booking_status, fare_amount, tax_amount, miles_earned)
SELECT b.booking_id,
       p.passenger_key,
       f.flight_key,
       bd.date_key,
       td.date_key,
       ao.airport_key,
       ad.airport_key,
       ac.aircraft_key,
       b.fare_class, b.booking_status, b.fare_amount, b.tax_amount, b.miles_earned
FROM bronze_bookings b
JOIN bronze_flights    bf ON bf.flight_id = b.flight_id
JOIN dw.DimPassenger   p  ON p.passenger_id = b.passenger_id
JOIN dw.DimFlight      f  ON f.flight_id = b.flight_id
JOIN dw.DimDate        bd ON bd.calendar_date = b.booking_date
JOIN dw.DimDate        td ON td.calendar_date = b.travel_date
JOIN dw.DimAirport     ao ON ao.airport_code = bf.origin_airport_code
JOIN dw.DimAirport     ad ON ad.airport_code = bf.dest_airport_code
JOIN dw.DimAircraft    ac ON ac.aircraft_code = bf.aircraft_code;

--Checks to run  criteria

-- 1. Row counts must match
SELECT (SELECT COUNT(*) FROM bronze_bookings)  AS bronze_rows,
       (SELECT COUNT(*) FROM dw.FactTicketSales) AS fact_rows;

-- 2. Every fact row resolves to all dimensions (expect 0)
SELECT COUNT(*) AS unresolved
FROM dw.FactTicketSales
WHERE passenger_key IS NULL OR flight_key IS NULL OR booking_date_key IS NULL
   OR travel_date_key IS NULL OR origin_airport_key IS NULL
   OR dest_airport_key IS NULL OR aircraft_key IS NULL;

-- 3. If counts differ, find what dropped (swap in each dimension)
SELECT b.booking_id
FROM bronze_bookings b
LEFT JOIN dw.FactTicketSales f ON f.booking_id = b.booking_id
WHERE f.booking_id IS NULL;


/*
4.
Snowflake the geography. Normalise the airport dimension into three linked
tables: airport, city, and country. Load them, and write one sentence on the trade-off you are making. 
Acceptance criteria: 
three linked tables with foreign keys; a query can resolve an airport all the way up to its country.
*/


SELECT country, COUNT(DISTINCT region) AS regions
FROM dw.DimAirport GROUP BY country HAVING COUNT(DISTINCT region) > 1;

SELECT city, COUNT(DISTINCT country) AS countries
FROM dw.DimAirport GROUP BY city HAVING COUNT(DISTINCT country) > 1;

--Corrected loads 
INSERT INTO dw.Country (country_key, country_name, region)
SELECT ROW_NUMBER() OVER (ORDER BY country), country, region
FROM dw.DimAirport
GROUP BY country, region;

INSERT INTO dw.City (city_key, city_name, country_key)
SELECT ROW_NUMBER() OVER (ORDER BY d.city), d.city, c.country_key
FROM dw.DimAirport d
JOIN dw.Country c ON c.country_name = d.country
GROUP BY d.city, c.country_key;

INSERT INTO dw.Airport (airport_key, airport_code, airport_name, city_key)
SELECT d.airport_key, d.airport_code, d.airport_name, ci.city_key
FROM dw.DimAirport d
JOIN dw.Country co ON co.country_name = d.country
JOIN dw.City    ci ON ci.city_name = d.city
                  AND ci.country_key = co.country_key;

-- Airport count should equal DimAirport (no loss, no duplicates)
SELECT (SELECT COUNT(*) FROM dw.DimAirport) AS flat_rows,
       (SELECT COUNT(*) FROM dw.Airport)    AS snowflake_rows;

-- Resolve airport all the way up to country
SELECT a.airport_code, a.airport_name, c.city_name, co.country_name, co.region
FROM dw.Airport a
JOIN dw.City    c  ON c.city_key = a.city_key
JOIN dw.Country co ON co.country_key = c.country_key;


/* Trade-off: normalising removes repeated city and country text and keeps
   geography consistent, but every query that needs country or region now
   pays for two extra joins. */


       /*
    5.
Rebuild the passenger dimension as Slowly Changing Dimension Type 2 (a new
surrogate key per version, the stable business key, is_current, effective_from, effective_to).
Apply stg_passenger_updates so that a changed tier or home airport expires the old version and opens a new one, 
and brand-new passengers are inserted.Acceptance criteria: the two-step expire-then-insert pattern is used;
a passenger who changed
shows two versions with correct is_current and effective dates; new passengers appear as a
single current row.
    */


    SELECT name FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dw.DimPassenger_old');

-- use the name returned above
ALTER TABLE dw.FactTicketSales DROP CONSTRAINT <fk_name_from_above>;
ALTER TABLE dw.FactTicketSales ADD CONSTRAINT FK_Fact_Passenger
    FOREIGN KEY (passenger_key) REFERENCES dw.DimPassenger(passenger_key);


    DECLARE @load_date DATE = CAST(GETDATE() AS DATE);

-- Capture the changes once (NULL-safe)
SELECT s.*
INTO #chg
FROM stg_passenger_updates s
JOIN dw.DimPassenger d
  ON d.passenger_id = s.passenger_id AND d.is_current = 1
WHERE EXISTS (SELECT s.home_airport_code, s.frequent_flyer_tier
              EXCEPT
              SELECT d.home_airport_code, d.frequent_flyer_tier);

-- Step 1: expire old versions
UPDATE d
SET d.is_current = 0,
    d.effective_to = @load_date
FROM dw.DimPassenger d
JOIN #chg c ON c.passenger_id = d.passenger_id
WHERE d.is_current = 1;

-- Step 2: open new versions for changed passengers
INSERT INTO dw.DimPassenger
(passenger_key, passenger_id, passenger_name, home_airport_code,
 frequent_flyer_tier, signup_date, is_current, effective_from, effective_to)
SELECT
    ROW_NUMBER() OVER (ORDER BY c.passenger_id)
      + (SELECT ISNULL(MAX(passenger_key), 0) FROM dw.DimPassenger),
    c.passenger_id, c.passenger_name, c.home_airport_code, c.frequent_flyer_tier,
    (SELECT MAX(signup_date) FROM dw.DimPassenger p WHERE p.passenger_id = c.passenger_id),
    1, @load_date, NULL
FROM #chg c;

-- Step 3: brand-new passengers
INSERT INTO dw.DimPassenger
(passenger_key, passenger_id, passenger_name, home_airport_code,
 frequent_flyer_tier, signup_date, is_current, effective_from, effective_to)
SELECT
    ROW_NUMBER() OVER (ORDER BY s.passenger_id)
      + (SELECT ISNULL(MAX(passenger_key), 0) FROM dw.DimPassenger),
    s.passenger_id, s.passenger_name, s.home_airport_code, s.frequent_flyer_tier,
    @load_date, 1, @load_date, NULL      -- use s.signup_date if the feed has it
FROM stg_passenger_updates s
WHERE NOT EXISTS (SELECT 1 FROM dw.DimPassenger d WHERE d.passenger_id = s.passenger_id);


-- Changed passengers show 2 versions with correct flags and dates
SELECT passenger_id, home_airport_code, frequent_flyer_tier,
       is_current, effective_from, effective_to
FROM dw.DimPassenger
WHERE passenger_id IN (SELECT passenger_id FROM #chg)
ORDER BY passenger_id, effective_from;

-- New passengers: one current row each
SELECT passenger_id, COUNT(*) AS versions, SUM(CAST(is_current AS INT)) AS current_rows
FROM dw.DimPassenger
WHERE passenger_id IN (SELECT passenger_id FROM stg_passenger_updates)
GROUP BY passenger_id
HAVING COUNT(*) = 1 AND SUM(CAST(is_current AS INT)) = 1;

-- Must return 0 rows: no passenger with more than one current row
SELECT passenger_id FROM dw.DimPassenger
WHERE is_current = 1 GROUP BY passenger_id HAVING COUNT(*) > 1;


/*
6.
The sales fact is the biggest table in the warehouse. Partition it by date
using a partition function and a partition scheme. 
Then run two queries: one that filters on the partition key, and one that filters on a non-partition column. 
Acceptance criteria: 
a partition function and scheme exist and the fact sits on the scheme; you show, using the actual execution plan, 
that the first query prunes to a small number of partitions and the second does not, and you explain why.
*/


-- Only if a clustered PK exists:
-- ALTER TABLE dw.FactTicketSales DROP CONSTRAINT <pk_name>;
-- ALTER TABLE dw.FactTicketSales ADD CONSTRAINT PK_FactTicketSales
--     PRIMARY KEY NONCLUSTERED (booking_id, calendar_key);

CREATE PARTITION FUNCTION pf_FactTicketSales_CalendarKey (INT)
AS RANGE RIGHT FOR VALUES
(20250101, 20250401, 20250701, 20251001,
 20260101, 20260401, 20260701);

CREATE PARTITION SCHEME ps_FactTicketSales_CalendarKey
AS PARTITION pf_FactTicketSales_CalendarKey
ALL TO ([PRIMARY]);

CREATE CLUSTERED INDEX IX_FactTicketSales_CalendarKey
ON dw.FactTicketSales (calendar_key)
ON ps_FactTicketSales_CalendarKey(calendar_key);

-- Rows per partition (confirm the spread is sensible)
SELECT $PARTITION.pf_FactTicketSales_CalendarKey(calendar_key) AS partition_number,
       COUNT(*) AS row_count
FROM dw.FactTicketSales
GROUP BY $PARTITION.pf_FactTicketSales_CalendarKey(calendar_key)
ORDER BY partition_number;

SET STATISTICS IO ON;

-- Q1: filters on the partition key -> expect 1 partition accessed
SELECT COUNT(*), SUM(fare_amount)
FROM dw.FactTicketSales
WHERE calendar_key >= 20250401 AND calendar_key < 20250701;

-- Q2: filters on a non-partition column -> expect all partitions accessed
SELECT COUNT(*), SUM(fare_amount)
FROM dw.FactTicketSales
WHERE passenger_key = 1001;



/*
(a) Map every table in this pipeline to a 
medallion layer (bronze, silver, or gold) and say in a line why each sits where. 
(b) Write a data contract for the bronze_bookings feed. Acceptance criteria: 
every table is assigned a layer with a short reason; the contract states the schema and types, 
the allowed values for fare_class and booking_status, a freshness or delivery SLA, the owner,
and one example each of a breaking and a non-breaking change.
Codebasics ·

*/

## (a) Medallion Layer Mapping

| Table | Layer | Reason |
|---|---|---|
| `bronze_bookings` | Bronze | Raw bookings landed as delivered from the booking system. |
| `bronze_passengers` | Bronze | Raw passenger records from the source, no transformation. |
| `bronze_flights` | Bronze | Raw flight records from the source. |
| `bronze_airports` | Bronze | Raw airport reference data. |
| `bronze_aircraft` | Bronze | Raw aircraft reference data. |
| `stg_passenger_updates` | Bronze | Raw daily passenger change feed; it only feeds the SCD2 load and nothing is cleaned in it. |
| `dw.DimDate` | Gold | Generated yyyymmdd calendar used by both date roles (booking and travel). |
| `dw.DimPassenger` | Gold | SCD Type 2 passenger history, so tier-based revenue stays accurate. |
| `dw.DimFlight` | Gold | Business-ready flight dimension with a surrogate key. |
| `dw.DimAirport` | Gold | Flat airport dimension, role-played as origin and destination. |
| `dw.DimAircraft` | Gold | Business-ready aircraft dimension. |
| `dw.Airport` | Gold | Snowflaked airport table, linked to city. |
| `dw.City` | Gold | Snowflaked city table, linked to country. |
| `dw.Country` | Gold | Snowflaked country table; top of the geography hierarchy. |
| `dw.FactTicketSales` | Gold | Ticket-grain fact with surrogate-key foreign keys and additive measures, partitioned by date. |
| `dw.DimPassenger_old` | Not in model | Pre-SCD2 backup table; drop it once the SCD2 checks pass. |

**Silver:** no separate Silver tables were built. The dimensions and fact load directly from Bronze. A Silver layer would hold deduplicated, typed and validated copies (for example, one row per `passenger_id` and only valid `fare_class` values).

## (b) Data Contract: `bronze_bookings`

**Purpose:** raw booking feed from the booking system, stored with minimal transformation.
**Grain:** one row per ticket sold (one passenger on one flight).
**Owner:** Vayu Air Booking Platform team (producer). Consumer: Analytics Engineering.
**Contact:** <team email / channel>

### Schema

| Column | Data Type | Nullable | Description |
|---|---|---|---|
| `booking_id` | INT | NOT NULL | Primary key, must be unique |
| `passenger_id` | VARCHAR(20) | NOT NULL | Must exist in `bronze_passengers` |
| `flight_id` | INT | NOT NULL | Must exist in `bronze_flights` |
| `booking_date` | DATE | NOT NULL | Date the booking was made |
| `travel_date` | DATE | NOT NULL | Date of travel, on or after `booking_date` |
| `fare_class` | VARCHAR(25) | NOT NULL | Ticket fare class |
| `booking_status` | VARCHAR(20) | NOT NULL | Current booking status |
| `fare_amount` | DECIMAL(12,2) | NOT NULL | Fare, must be >= 0 |
| `tax_amount` | DECIMAL(12,2) | NOT NULL | Tax, must be >= 0 |
| `miles_earned` | INT | NULL | Frequent-flyer miles earned, must be >= 0 |

### Allowed Values

- **`fare_class`:** Economy, Premium Economy, Business, First
- **`booking_status`:** Confirmed, Cancelled, NoShow

Rows with any other value are quarantined and reported to the owner.

### Freshness / Delivery SLA

- Delivered **daily by 06:00 UTC**.
- Each delivery contains all bookings up to the end of the previous day.
- A late or failed delivery is reported to the owner and the Analytics Engineering lead within 1 hour.

### Change Management

Breaking changes need 30 days' notice and a version bump. Non-breaking changes need notice by the next delivery.

### Breaking Change (example)

Changing `fare_amount` from DECIMAL to VARCHAR. Downstream joins and sums expect a numeric value, so loads would fail or give wrong totals.

### Non-Breaking Change (example)

Adding a new optional column such as `booking_channel`. Existing columns and their definitions stay the same, so current queries keep working.