# 🏗️ Modern Data Warehouse with SQL Server

> A modern, scalable, and sustainable data warehouse built on SQL Server — covering architecture, ETL processes, data modeling, and analytics.

---

## 📑 Table of Contents

- [Project Overview](#-project-overview)
- [Architecture](#-architecture)
  - [Medallion Layers](#medallion-layers)
  - [Layer Responsibilities](#layer-responsibilities)
- [ETL Processes](#-etl-processes)
  - [Extract](#1-extract)
  - [Transform](#2-transform)
  - [Load](#3-load)
  - [ETL Best Practices](#etl-best-practices)
- [Data Modeling](#-data-modeling)
  - [Star Schema](#star-schema)
  - [Fact Tables](#fact-tables)
  - [Dimension Tables](#dimension-tables)
  - [Slowly Changing Dimensions](#slowly-changing-dimensions-scd)
- [Data Analytics](#-data-analytics)
  - [Analytical Queries](#analytical-queries)
  - [Window Functions](#window-functions)
- [SQL Server Features](#-sql-server-features)
- [Project Structure](#-project-structure)
- [Naming Conventions](#-naming-conventions)
- [Sustainability Practices](#-sustainability-practices)
- [Getting Started](#-getting-started)
- [Contributing](#-contributing)

---

## 📌 Project Overview

This project implements a **modern, sustainable data warehouse** using SQL Server. It is designed to consolidate data from multiple source systems, apply consistent transformations, and serve clean, reliable data for business intelligence and analytics.

**Key goals:**

- Centralize data from disparate source systems into a single source of truth
- Apply consistent data quality rules and business logic
- Deliver fast, reliable analytical queries for reporting and dashboards
- Maintain a clean, documented, and reproducible codebase

**Tech stack:**

| Component | Technology |
|-----------|-----------|
| Database engine | SQL Server 2019+ |
| ETL orchestration | SSIS / T-SQL Stored Procedures |
| Scheduling | SQL Server Agent |
| Reporting | Power BI / SSRS |
| Version control | Git |

---

## 🏛️ Architecture

This warehouse follows the **Medallion Architecture** — a three-layer design pattern that separates raw ingestion, cleansing, and analytics into distinct, purpose-built layers.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA WAREHOUSE                              │
│                                                                     │
│  ┌──────────┐    ETL    ┌──────────┐    ETL    ┌──────────────┐    │
│  │  BRONZE  │ ────────► │  SILVER  │ ────────► │     GOLD     │    │
│  │          │           │          │           │              │    │
│  │  Raw /   │           │Cleansed /│           │  Analytics / │    │
│  │ Landing  │           │Conformed │           │   Business   │    │
│  └──────────┘           └──────────┘           └──────────────┘    │
│       ▲                                               │             │
└───────┼───────────────────────────────────────────────┼─────────────┘
        │                                               │
  ┌─────┴──────┐                              ┌─────────▼────────┐
  │  SOURCES   │                              │   CONSUMERS      │
  │            │                              │                  │
  │ ERP / CRM  │                              │ Power BI / SSRS  │
  │ Databases  │                              │ SQL Analytics    │
  │ CSV / APIs │                              │ Data Science     │
  │ IoT / Logs │                              │ ML Pipelines     │
  └────────────┘                              └──────────────────┘
```

### Medallion Layers

| Layer | Schema | Purpose |
|-------|--------|---------|
| 🥉 Bronze | `bronze` | Raw data — exactly as received from sources |
| 🥈 Silver | `silver` | Cleansed, standardized, and deduplicated data |
| 🥇 Gold | `gold` | Modeled, aggregated data ready for analytics |

### Layer Responsibilities

**🥉 Bronze — Raw / Landing Zone**

- Stores data exactly as it arrived from source systems — no transformations
- Acts as a replayable archive; if downstream breaks, reload from here
- Captures audit metadata: `load_timestamp`, `source_system`, `batch_id`
- Supports both full loads and incremental loads

**🥈 Silver — Cleansed / Conformed**

- Applies data type enforcement and null handling
- Removes duplicates and resolves conflicts across sources
- Applies business rules and standardizes formats (dates, casing, codes)
- Assigns surrogate keys to replace source business keys

**🥇 Gold — Analytics / Business**

- Star schema: fact tables and dimension tables
- Pre-aggregated tables and summary views for fast reporting
- Optimized with columnstore indexes for analytical queries
- The only layer exposed to end-user tools and dashboards

---

## ⚙️ ETL Processes

ETL (Extract, Transform, Load) is the pipeline that moves data from sources through the medallion layers. All ETL logic lives in versioned stored procedures under `etl/`.

### 1. Extract

Data is pulled from source systems into the bronze layer.

**Two load strategies:**

```
Full Load       — Copy all records every run. Simple. Use for small tables or 
                  sources without change-tracking.

Incremental     — Copy only records changed since the last run. Scalable. 
Load              Detected via ModifiedDate column, rowversion, or CDC.
```

**Example — incremental extract into bronze:**

```sql
-- etl/bronze/load_bronze_customers.sql
INSERT INTO bronze.raw_customers (
    customer_id, first_name, last_name, email,
    phone, country, modified_date, load_timestamp, batch_id
)
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    c.country,
    c.modified_date,
    GETDATE()       AS load_timestamp,
    @batch_id       AS batch_id
FROM source_crm.dbo.customers c
WHERE c.modified_date > (
    SELECT ISNULL(MAX(modified_date), '1900-01-01')
    FROM bronze.raw_customers
);
```

### 2. Transform

Bronze data is cleaned and standardized into the silver layer.

**Example — clean and load silver customers:**

```sql
-- etl/silver/load_silver_customers.sql
INSERT INTO silver.customers (
    customer_id, full_name, email, country, load_date
)
SELECT
    customer_id,
    TRIM(
        UPPER(LEFT(first_name, 1)) + LOWER(SUBSTRING(first_name, 2, 100))
        + ' ' +
        UPPER(LEFT(last_name, 1))  + LOWER(SUBSTRING(last_name, 2, 100))
    )                   AS full_name,
    LOWER(TRIM(email))  AS email,
    UPPER(TRIM(country)) AS country,
    GETDATE()           AS load_date
FROM bronze.raw_customers
WHERE email      IS NOT NULL
  AND customer_id IS NOT NULL
  AND customer_id NOT IN (
      SELECT customer_id FROM silver.customers
  );
```

**Common transformations applied in silver:**

| Transformation | Example |
|----------------|---------|
| Trim whitespace | `TRIM(column_name)` |
| Standardize case | `UPPER()`, `LOWER()`, title case logic |
| Parse dates | `TRY_CONVERT(DATE, date_string, 103)` |
| Handle nulls | `ISNULL(column, 'Unknown')` |
| Validate emails | `LIKE '%@%.%'` pattern check |
| Remove duplicates | `ROW_NUMBER() OVER (PARTITION BY id ORDER BY load_ts DESC)` |

### 3. Load

Silver data is shaped into star schema tables in the gold layer.

**Example — load dimension table with upsert:**

```sql
-- etl/gold/load_dim_customer.sql
MERGE gold.dim_customer AS target
USING (
    SELECT
        customer_id,
        full_name,
        email,
        country,
        GETDATE() AS valid_from,
        '9999-12-31' AS valid_to,
        1 AS is_current
    FROM silver.customers
) AS source
ON target.customer_id = source.customer_id AND target.is_current = 1

WHEN MATCHED AND (
    target.full_name <> source.full_name OR
    target.email     <> source.email     OR
    target.country   <> source.country
) THEN
    UPDATE SET
        target.is_current = 0,
        target.valid_to   = GETDATE()

WHEN NOT MATCHED BY TARGET THEN
    INSERT (customer_id, full_name, email, country, valid_from, valid_to, is_current)
    VALUES (source.customer_id, source.full_name, source.email,
            source.country, source.valid_from, source.valid_to, source.is_current);
```

**Example — load fact table:**

```sql
-- etl/gold/load_fact_sales.sql
INSERT INTO gold.fact_sales (
    customer_key, product_key, date_key,
    quantity, unit_price, total_amount
)
SELECT
    dc.customer_key,
    dp.product_key,
    dd.date_key,
    s.quantity,
    s.unit_price,
    s.quantity * s.unit_price   AS total_amount
FROM silver.sales         s
JOIN gold.dim_customer    dc ON s.customer_id = dc.customer_id AND dc.is_current = 1
JOIN gold.dim_product     dp ON s.product_id  = dp.product_id  AND dp.is_current = 1
JOIN gold.dim_date        dd ON CAST(s.sale_date AS DATE) = dd.full_date
WHERE s.sale_id NOT IN (SELECT sale_id FROM gold.fact_sales);
```

### ETL Best Practices

- **Log every batch run** — record start time, end time, rows processed, and status into an `etl.batch_log` table
- **Wrap loads in transactions** — a failed load leaves the table unchanged
- **Build idempotent procedures** — safe to rerun without duplicating data
- **Validate after loading** — check row counts, nulls, and referential integrity
- **Never modify bronze** — it is your recovery point; treat it as append-only

---

## 📐 Data Modeling

The gold layer uses a **Star Schema** — the industry standard for analytical data warehouses. It optimizes for fast aggregation queries and simplicity for business users.

### Star Schema

```
                         ┌─────────────────┐
                         │   dim_date      │
                         │─────────────────│
                         │ date_key (PK)   │
                         │ full_date       │
                         │ day_of_week     │
                         │ month_name      │
                         │ quarter         │
                         │ year_number     │
                         └────────┬────────┘
                                  │
              ┌───────────────────┼────────────────────┐
              │                   │                    │
   ┌──────────┴──────┐   ┌────────▼────────┐  ┌───────┴────────┐
   │  dim_customer   │   │   fact_sales    │  │  dim_product   │
   │─────────────────│   │─────────────────│  │────────────────│
   │ customer_key(PK)│◄──│ customer_key(FK)│  │ product_key(PK)│
   │ customer_id     │   │ product_key(FK) │──►│ product_id     │
   │ full_name       │   │ date_key    (FK)│  │ product_name   │
   │ email           │   │ location_key(FK)│  │ category       │
   │ country         │   │─────────────────│  │ sub_category   │
   │ segment         │   │ quantity        │  │ unit_cost      │
   │ is_current      │   │ unit_price      │  │ is_current     │
   │ valid_from      │   │ total_amount    │  └────────────────┘
   │ valid_to        │   │ discount_amount │
   └─────────────────┘   └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │  dim_location   │
                         │─────────────────│
                         │ location_key(PK)│
                         │ city            │
                         │ region          │
                         │ country         │
                         └─────────────────┘
```

### Fact Tables

Fact tables record measurable business events. Each row represents one event (a sale, a shipment, a page view).

```sql
-- gold/tables/fact_sales.sql
CREATE TABLE gold.fact_sales (
    sale_id          INT            NOT NULL,
    customer_key     INT            NOT NULL,
    product_key      INT            NOT NULL,
    date_key         INT            NOT NULL,
    location_key     INT            NOT NULL,
    quantity         INT            NOT NULL,
    unit_price       DECIMAL(10, 2) NOT NULL,
    discount_amount  DECIMAL(10, 2) NOT NULL DEFAULT 0,
    total_amount     DECIMAL(10, 2) NOT NULL,

    CONSTRAINT pk_fact_sales      PRIMARY KEY (sale_id),
    CONSTRAINT fk_fs_customer     FOREIGN KEY (customer_key)  REFERENCES gold.dim_customer (customer_key),
    CONSTRAINT fk_fs_product      FOREIGN KEY (product_key)   REFERENCES gold.dim_product  (product_key),
    CONSTRAINT fk_fs_date         FOREIGN KEY (date_key)      REFERENCES gold.dim_date     (date_key),
    CONSTRAINT fk_fs_location     FOREIGN KEY (location_key)  REFERENCES gold.dim_location (location_key)
);

-- Columnstore index for fast analytical queries
CREATE NONCLUSTERED COLUMNSTORE INDEX ncci_fact_sales
ON gold.fact_sales (customer_key, product_key, date_key, total_amount, quantity);
```

### Dimension Tables

Dimension tables hold descriptive context for the facts — who, what, when, where.

```sql
-- gold/tables/dim_customer.sql
CREATE TABLE gold.dim_customer (
    customer_key     INT            NOT NULL IDENTITY(1, 1),
    customer_id      VARCHAR(50)    NOT NULL,
    full_name        NVARCHAR(200)  NOT NULL,
    email            VARCHAR(255),
    country          VARCHAR(100),
    segment          VARCHAR(50),
    is_current       BIT            NOT NULL DEFAULT 1,
    valid_from       DATE           NOT NULL,
    valid_to         DATE           NOT NULL DEFAULT '9999-12-31',

    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key)
);

-- gold/tables/dim_date.sql
CREATE TABLE gold.dim_date (
    date_key         INT            NOT NULL,  -- format: YYYYMMDD
    full_date        DATE           NOT NULL,
    day_of_week      TINYINT        NOT NULL,
    day_name         VARCHAR(10)    NOT NULL,
    month_number     TINYINT        NOT NULL,
    month_name       VARCHAR(10)    NOT NULL,
    quarter          TINYINT        NOT NULL,
    year_number      SMALLINT       NOT NULL,
    is_weekend       BIT            NOT NULL,
    is_holiday       BIT            NOT NULL DEFAULT 0,

    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);
```

### Slowly Changing Dimensions (SCD)

Dimensions change over time. The SCD type determines how history is handled.

| Type | Description | When to use |
|------|-------------|-------------|
| **Type 1** | Overwrite — no history kept | Corrections, non-critical attributes |
| **Type 2** | Add new row — full history | Customer address, product price, employee department |
| **Type 3** | Add column — limited history | When only "current" and "previous" matter |

**Type 2 SCD pattern** (used in `dim_customer`):

```
Before change:
customer_key | customer_id | country   | is_current | valid_from | valid_to
101          | C001        | Kenya     | 1          | 2023-01-01 | 9999-12-31

After customer moves to Ethiopia:
customer_key | customer_id | country   | is_current | valid_from | valid_to
101          | C001        | Kenya     | 0          | 2023-01-01 | 2025-06-14
102          | C001        | Ethiopia  | 1          | 2025-06-15 | 9999-12-31
```

---

## 📊 Data Analytics

With the gold layer in place, analysts and BI tools query clean, well-structured data.

### Analytical Queries

**Revenue by category and month:**

```sql
SELECT
    d.year_number,
    d.month_name,
    p.category,
    SUM(f.total_amount)           AS total_revenue,
    COUNT(DISTINCT f.sale_id)     AS total_orders,
    AVG(f.total_amount)           AS avg_order_value,
    SUM(f.quantity)               AS total_units_sold
FROM gold.fact_sales           f
JOIN gold.dim_date             d ON f.date_key     = d.date_key
JOIN gold.dim_product          p ON f.product_key  = p.product_key
JOIN gold.dim_customer         c ON f.customer_key = c.customer_key
WHERE d.year_number = 2025
GROUP BY d.year_number, d.month_name, d.month_number, p.category
ORDER BY d.year_number, d.month_number, total_revenue DESC;
```

**Top 10 customers by revenue:**

```sql
SELECT TOP 10
    c.full_name,
    c.country,
    SUM(f.total_amount)       AS total_spent,
    COUNT(DISTINCT f.sale_id) AS total_orders,
    MIN(d.full_date)          AS first_purchase,
    MAX(d.full_date)          AS last_purchase
FROM gold.fact_sales     f
JOIN gold.dim_customer   c ON f.customer_key = c.customer_key AND c.is_current = 1
JOIN gold.dim_date       d ON f.date_key     = d.date_key
GROUP BY c.full_name, c.country
ORDER BY total_spent DESC;
```

### Window Functions

Window functions are the most powerful analytical tool for warehouse queries.

**Running total and rank within category:**

```sql
SELECT
    d.month_name,
    p.product_name,
    p.category,
    SUM(f.total_amount)   AS monthly_revenue,

    -- Running total within each category
    SUM(SUM(f.total_amount)) OVER (
        PARTITION BY p.category
        ORDER BY d.year_number, d.month_number
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                     AS running_category_total,

    -- Month-over-month growth
    LAG(SUM(f.total_amount), 1) OVER (
        PARTITION BY p.product_name
        ORDER BY d.year_number, d.month_number
    )                     AS prev_month_revenue,

    -- Revenue rank within category
    RANK() OVER (
        PARTITION BY p.category, d.month_number
        ORDER BY SUM(f.total_amount) DESC
    )                     AS revenue_rank

FROM gold.fact_sales       f
JOIN gold.dim_date         d ON f.date_key    = d.date_key
JOIN gold.dim_product      p ON f.product_key = p.product_key
WHERE d.year_number = 2025
GROUP BY d.year_number, d.month_number, d.month_name, p.product_name, p.category
ORDER BY p.category, d.month_number, monthly_revenue DESC;
```

---

## 🛠️ SQL Server Features

| Feature | Layer | Purpose |
|---------|-------|---------|
| **SSIS** | All | ETL orchestration, file ingestion, scheduling |
| **SQL Server Agent** | All | Schedule stored procedures and SSIS packages |
| **Columnstore indexes** | Gold | 10–100× faster analytical queries on fact tables |
| **Table partitioning** | Bronze, Gold | Partition by year/month for faster queries and archiving |
| **Views** | Gold | Clean interfaces for BI tools without exposing raw tables |
| **T-SQL MERGE** | Silver, Gold | Efficient upserts in dimension and fact loads |
| **CDC (Change Data Capture)** | Bronze | Detect source changes without touching source systems |
| **Temporal tables** | Silver | Built-in history tracking managed by SQL Server |
| **TRY_CONVERT / TRY_CAST** | Silver | Safe type conversions that return NULL instead of failing |
| **STRING_SPLIT / JSON** | Silver | Handle semi-structured source data |

---

## 📁 Project Structure

```
data-warehouse/
│
├── README.md
│
├── database/
│   ├── create_database.sql          -- Create DW database and schemas
│   └── create_schemas.sql           -- bronze, silver, gold, etl schemas
│
├── bronze/
│   └── tables/
│       ├── raw_customers.sql
│       ├── raw_products.sql
│       └── raw_sales.sql
│
├── silver/
│   └── tables/
│       ├── customers.sql
│       ├── products.sql
│       └── sales.sql
│
├── gold/
│   ├── tables/
│   │   ├── dim_customer.sql
│   │   ├── dim_product.sql
│   │   ├── dim_date.sql
│   │   ├── dim_location.sql
│   │   └── fact_sales.sql
│   └── views/
│       ├── vw_sales_summary.sql
│       └── vw_customer_lifetime_value.sql
│
├── etl/
│   ├── bronze/
│   │   ├── load_bronze_customers.sql
│   │   ├── load_bronze_products.sql
│   │   └── load_bronze_sales.sql
│   ├── silver/
│   │   ├── load_silver_customers.sql
│   │   ├── load_silver_products.sql
│   │   └── load_silver_sales.sql
│   └── gold/
│       ├── load_dim_customer.sql
│       ├── load_dim_product.sql
│       ├── load_dim_date.sql
│       ├── load_fact_sales.sql
│       └── master_load.sql          -- Runs all loads in order
│
├── analytics/
│   ├── revenue_by_category.sql
│   ├── top_customers.sql
│   └── monthly_trends.sql
│
├── tests/
│   ├── test_row_counts.sql
│   ├── test_referential_integrity.sql
│   └── test_null_checks.sql
│
└── docs/
    ├── data_dictionary.md
    ├── architecture_diagram.png
    └── erd.png
```

---

## 📝 Naming Conventions

Consistent naming is critical for maintainability.

| Object | Convention | Example |
|--------|-----------|---------|
| Schemas | layer name | `bronze`, `silver`, `gold`, `etl` |
| Tables | snake_case, with prefix | `dim_customer`, `fact_sales`, `raw_orders` |
| Views | `vw_` prefix | `vw_sales_summary` |
| Stored procedures | `sp_load_` prefix | `sp_load_dim_customer` |
| Indexes | type + table + columns | `ncci_fact_sales`, `ix_dim_customer_id` |
| Primary keys | `pk_` prefix | `pk_fact_sales` |
| Foreign keys | `fk_` prefix + table abbreviation | `fk_fs_customer` |
| Surrogate keys | `_key` suffix | `customer_key` |
| Business / source keys | `_id` suffix | `customer_id` |
| Date columns | descriptive suffix | `load_date`, `valid_from`, `valid_to` |
| Boolean/flag columns | `is_` prefix | `is_current`, `is_active`, `is_weekend` |

---

## 🌱 Sustainability Practices

A warehouse that's hard to maintain will be abandoned. These practices keep it sustainable long-term.

**Code quality**
- All ETL logic lives in stored procedures — no ad-hoc scripts in production
- Every procedure is idempotent (safe to rerun)
- All scripts are version-controlled in Git with meaningful commit messages
- Stored procedures accept a `@batch_id` parameter for traceability

**Observability**
- Every ETL run is logged to `etl.batch_log`: batch ID, start time, end time, rows loaded, status, and any error message
- Data quality checks run automatically after each load and log failures
- SQL Server Agent sends alerts on job failure

**Data quality checks**

```sql
-- tests/test_row_counts.sql
-- Ensure silver has no fewer rows than bronze (after filter for valid records)
SELECT
    'Customer count check' AS test_name,
    CASE
        WHEN (SELECT COUNT(*) FROM silver.customers) >= 
             (SELECT COUNT(*) FROM bronze.raw_customers WHERE email IS NOT NULL)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result;
```

**Documentation**
- A `docs/data_dictionary.md` defines every table and column
- ERD diagrams are kept up to date
- Complex stored procedures have a header comment block explaining purpose, parameters, and schedule

**Separation of concerns**
- Sources never write directly to silver or gold — always through bronze first
- BI tools connect only to gold views, never to underlying tables
- No business logic in the reporting layer — it belongs in silver/gold

---

## 🚀 Getting Started

### Prerequisites

- SQL Server 2019 or later
- SQL Server Management Studio (SSMS) 19+
- SQL Server Integration Services (SSIS) — optional for file-based sources
- Git

### Setup steps

**1. Create the database and schemas**

```sql
-- Run: database/create_database.sql
CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;
CREATE SCHEMA etl;
GO
```

**2. Create tables — run in order**

```bash
# Bronze layer
scripts/bronze/tables/raw_customers.sql
scripts/bronze/tables/raw_products.sql
scripts/bronze/tables/raw_sales.sql

# Silver layer
scripts/silver/tables/customers.sql
scripts/silver/tables/products.sql
scripts/silver/tables/sales.sql

# Gold layer
scripts/gold/tables/dim_date.sql
scripts/gold/tables/dim_customer.sql
scripts/gold/tables/dim_product.sql
scripts/gold/tables/dim_location.sql
scripts/gold/tables/fact_sales.sql
```

**3. Populate the date dimension** (run once)

```sql
-- Generates date records from 2020-01-01 to 2030-12-31
EXEC etl.sp_populate_dim_date @start_date = '2020-01-01', @end_date = '2030-12-31';
```

**4. Run the initial full load**

```sql
EXEC etl.sp_master_load @load_type = 'FULL';
```

**5. Schedule incremental loads**

Set up a SQL Server Agent job to run daily:

```sql
EXEC etl.sp_master_load @load_type = 'INCREMENTAL';
```

---

## 🤝 Contributing

1. Fork the repository and create a feature branch: `git checkout -b feature/add-dim-employee`
2. Follow the naming conventions and project structure above
3. Test all new ETL procedures with the scripts in `tests/`
4. Update `docs/data_dictionary.md` for any new tables or columns
5. Submit a pull request with a clear description of what changed and why

---

## 📄 License

This project is licensed under the MIT License. See `LICENSE` for details.

---

*Built with SQL Server · Designed for scale · Maintained for people*
