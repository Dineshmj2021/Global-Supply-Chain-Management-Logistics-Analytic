-- ============================================================================
-- SUPPLY CHAIN MANAGEMENT ANALYTICS DATABASE (SupplyChainDB)
-- Script: table_creation.sql
-- Description: DDL definitions for Star Schema Dimension & Fact tables,
--              including Primary Keys, Foreign Keys, Constraints, and Indexes.
-- ============================================================================

-- Switch to Core Schema
SET search_path TO core, public;

-- Drop existing tables if re-running (Fact tables first due to FK constraints)
DROP TABLE IF EXISTS core.fact_orders_shipments CASCADE;
DROP TABLE IF EXISTS core.fact_inventory_levels CASCADE;
DROP TABLE IF EXISTS core.fact_procurement_pos CASCADE;
DROP TABLE IF EXISTS core.dim_customers CASCADE;
DROP TABLE IF EXISTS core.dim_products CASCADE;
DROP TABLE IF EXISTS core.dim_suppliers CASCADE;
DROP TABLE IF EXISTS core.dim_warehouses CASCADE;
DROP TABLE IF EXISTS core.dim_carriers CASCADE;
DROP TABLE IF EXISTS core.dim_date CASCADE;

-- ============================================================================
-- 1. DIMENSION TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 Date Dimension (dim_date)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_date (
    date_key               DATE PRIMARY KEY,
    year_num               SMALLINT NOT NULL,
    quarter_num            SMALLINT NOT NULL CHECK (quarter_num BETWEEN 1 AND 4),
    quarter_name           VARCHAR(6) NOT NULL,       -- e.g., 'Q1'
    month_number           SMALLINT NOT NULL CHECK (month_number BETWEEN 1 AND 12),
    month_name             VARCHAR(15) NOT NULL,      -- e.g., 'January'
    month_short            VARCHAR(3) NOT NULL,       -- e.g., 'Jan'
    month_year             VARCHAR(8) NOT NULL,       -- e.g., '2024-01'
    day_of_month           SMALLINT NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
    day_name               VARCHAR(10) NOT NULL,      -- e.g., 'Monday'
    day_short              VARCHAR(3) NOT NULL,       -- e.g., 'Mon'
    day_of_week            SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    is_weekend             BOOLEAN NOT NULL,
    week_of_year           SMALLINT NOT NULL CHECK (week_of_year BETWEEN 1 AND 53),
    fiscal_quarter         VARCHAR(6) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 1.2 Carriers Dimension (dim_carriers)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_carriers (
    carrier_id             VARCHAR(10) PRIMARY KEY,
    carrier_name           VARCHAR(50) NOT NULL,
    transit_mode           VARCHAR(20) NOT NULL CHECK (transit_mode IN ('Air Express', 'Road Freight', 'Ocean Cargo', 'Rail Freight')),
    target_sla_days        DECIMAL(4,1) NOT NULL CHECK (target_sla_days > 0),
    cost_per_kg_km         DECIMAL(6,4) NOT NULL CHECK (cost_per_kg_km >= 0),
    reliability_rating     DECIMAL(3,2) NOT NULL CHECK (reliability_rating BETWEEN 0 AND 5)
);

-- ----------------------------------------------------------------------------
-- 1.3 Suppliers Dimension (dim_suppliers)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_suppliers (
    supplier_id            VARCHAR(10) PRIMARY KEY,
    supplier_name          VARCHAR(100) NOT NULL,
    country                VARCHAR(50) NOT NULL,
    region                 VARCHAR(50) NOT NULL,
    supplier_tier          VARCHAR(20) NOT NULL CHECK (supplier_tier IN ('Tier 1 Strategic', 'Tier 2 Preferred', 'Tier 3 Standard')),
    target_lead_time_days  INTEGER NOT NULL CHECK (target_lead_time_days > 0),
    target_otif_pct        DECIMAL(5,4) NOT NULL CHECK (target_otif_pct BETWEEN 0 AND 1)
);

-- ----------------------------------------------------------------------------
-- 1.4 Products Dimension (dim_products)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_products (
    product_id             VARCHAR(15) PRIMARY KEY,
    product_name           VARCHAR(120) NOT NULL,
    category               VARCHAR(50) NOT NULL,
    subcategory            VARCHAR(50) NOT NULL,
    abc_category           CHAR(1) NOT NULL CHECK (abc_category IN ('A', 'B', 'C')),
    unit_cost              DECIMAL(12,2) NOT NULL CHECK (unit_cost >= 0),
    unit_price             DECIMAL(12,2) NOT NULL CHECK (unit_price >= unit_cost),
    gross_margin_pct       DECIMAL(6,4) NOT NULL,
    lead_time_days         INTEGER NOT NULL CHECK (lead_time_days >= 0),
    primary_supplier_id    VARCHAR(10) NOT NULL REFERENCES core.dim_suppliers(supplier_id)
);

-- ----------------------------------------------------------------------------
-- 1.5 Warehouses Dimension (dim_warehouses)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_warehouses (
    warehouse_id           VARCHAR(10) PRIMARY KEY,
    warehouse_name         VARCHAR(80) NOT NULL,
    country                VARCHAR(50) NOT NULL,
    region                 VARCHAR(50) NOT NULL,
    city                   VARCHAR(50) NOT NULL,
    max_capacity_units     INTEGER NOT NULL CHECK (max_capacity_units > 0),
    manager_name           VARCHAR(80) NOT NULL,
    daily_operating_cost   DECIMAL(10,2) NOT NULL CHECK (daily_operating_cost >= 0)
);

-- ----------------------------------------------------------------------------
-- 1.6 Customers Dimension (dim_customers)
-- ----------------------------------------------------------------------------
CREATE TABLE core.dim_customers (
    customer_id            VARCHAR(15) PRIMARY KEY,
    customer_name          VARCHAR(100) NOT NULL,
    country                VARCHAR(50) NOT NULL,
    region                 VARCHAR(50) NOT NULL,
    customer_segment       VARCHAR(30) NOT NULL CHECK (customer_segment IN ('Enterprise', 'Mid-Market', 'Strategic Account')),
    credit_rating          VARCHAR(5) NOT NULL,
    account_manager        VARCHAR(30) NOT NULL
);

-- ============================================================================
-- 2. FACT TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 Orders & Shipments Fact (fact_orders_shipments)
-- Grain: One record per customer order line item shipment
-- ----------------------------------------------------------------------------
CREATE TABLE core.fact_orders_shipments (
    order_id               VARCHAR(20) PRIMARY KEY,
    order_date             DATE NOT NULL REFERENCES core.dim_date(date_key),
    ship_date              DATE REFERENCES core.dim_date(date_key),
    promised_delivery_date DATE NOT NULL REFERENCES core.dim_date(date_key),
    actual_delivery_date   DATE REFERENCES core.dim_date(date_key),
    customer_id            VARCHAR(15) NOT NULL REFERENCES core.dim_customers(customer_id),
    customer_country       VARCHAR(50) NOT NULL,
    product_id             VARCHAR(15) NOT NULL REFERENCES core.dim_products(product_id),
    warehouse_id           VARCHAR(10) NOT NULL REFERENCES core.dim_warehouses(warehouse_id),
    carrier_id             VARCHAR(10) NOT NULL REFERENCES core.dim_carriers(carrier_id),
    order_priority         VARCHAR(15) NOT NULL CHECK (order_priority IN ('Critical', 'High', 'Medium', 'Low')),
    order_quantity         INTEGER NOT NULL CHECK (order_quantity > 0),
    delivered_quantity     INTEGER NOT NULL CHECK (delivered_quantity >= 0),
    unit_sale_price        DECIMAL(12,2) NOT NULL CHECK (unit_sale_price >= 0),
    unit_cost              DECIMAL(12,2) NOT NULL CHECK (unit_cost >= 0),
    gross_revenue          DECIMAL(14,2) NOT NULL CHECK (gross_revenue >= 0),
    cogs                   DECIMAL(14,2) NOT NULL CHECK (cogs >= 0),
    gross_profit           DECIMAL(14,2) NOT NULL,
    freight_cost           DECIMAL(12,2) NOT NULL CHECK (freight_cost >= 0),
    net_margin             DECIMAL(14,2) NOT NULL,
    ontime_flag            SMALLINT NOT NULL CHECK (ontime_flag IN (0, 1)),
    infull_flag            SMALLINT NOT NULL CHECK (infull_flag IN (0, 1)),
    otif_flag              SMALLINT NOT NULL CHECK (otif_flag IN (0, 1)),
    delivery_delay_days    INTEGER NOT NULL DEFAULT 0,
    fulfillment_cycle_days INTEGER NOT NULL DEFAULT 0,
    return_flag            SMALLINT NOT NULL CHECK (return_flag IN (0, 1)),
    return_reason          VARCHAR(50) NOT NULL DEFAULT 'None',
    shipping_status        VARCHAR(25) NOT NULL CHECK (shipping_status IN ('Delivered On-Time', 'Delivered Late', 'In Transit', 'Returned', 'Cancelled'))
);

-- ----------------------------------------------------------------------------
-- 2.2 Inventory Levels Fact (fact_inventory_levels)
-- Grain: One record per Product per Warehouse per Snapshot Date
-- ----------------------------------------------------------------------------
CREATE TABLE core.fact_inventory_levels (
    inventory_snapshot_id  SERIAL PRIMARY KEY,
    snapshot_date          DATE NOT NULL REFERENCES core.dim_date(date_key),
    warehouse_id           VARCHAR(10) NOT NULL REFERENCES core.dim_warehouses(warehouse_id),
    product_id             VARCHAR(15) NOT NULL REFERENCES core.dim_products(product_id),
    stock_on_hand          INTEGER NOT NULL CHECK (stock_on_hand >= 0),
    safety_stock           INTEGER NOT NULL CHECK (safety_stock >= 0),
    reorder_point          INTEGER NOT NULL CHECK (reorder_point >= 0),
    average_daily_usage    DECIMAL(8,2) NOT NULL CHECK (average_daily_usage >= 0),
    days_of_supply_on_hand DECIMAL(8,1) NOT NULL CHECK (days_of_supply_on_hand >= 0),
    stockout_risk_flag     SMALLINT NOT NULL CHECK (stockout_risk_flag IN (0, 1)),
    overstock_flag         SMALLINT NOT NULL CHECK (overstock_flag IN (0, 1)),
    inventory_value_usd    DECIMAL(14,2) NOT NULL CHECK (inventory_value_usd >= 0),
    stock_status           VARCHAR(25) NOT NULL CHECK (stock_status IN ('Optimal', 'Low Stock Risk', 'Critical Stockout', 'Overstocked'))
);

-- ----------------------------------------------------------------------------
-- 2.3 Procurement Purchase Orders Fact (fact_procurement_pos)
-- Grain: One record per Purchase Order line item
-- ----------------------------------------------------------------------------
CREATE TABLE core.fact_procurement_pos (
    po_number              VARCHAR(20) PRIMARY KEY,
    po_date                DATE NOT NULL REFERENCES core.dim_date(date_key),
    promised_receipt_date  DATE NOT NULL REFERENCES core.dim_date(date_key),
    actual_receipt_date    DATE REFERENCES core.dim_date(date_key),
    supplier_id            VARCHAR(10) NOT NULL REFERENCES core.dim_suppliers(supplier_id),
    product_id             VARCHAR(15) NOT NULL REFERENCES core.dim_products(product_id),
    target_warehouse_id    VARCHAR(10) NOT NULL REFERENCES core.dim_warehouses(warehouse_id),
    ordered_qty            INTEGER NOT NULL CHECK (ordered_qty > 0),
    received_qty           INTEGER NOT NULL CHECK (received_qty >= 0),
    defect_qty             INTEGER NOT NULL CHECK (defect_qty >= 0),
    po_unit_cost           DECIMAL(12,2) NOT NULL CHECK (po_unit_cost >= 0),
    total_spend_usd        DECIMAL(14,2) NOT NULL CHECK (total_spend_usd >= 0),
    supplier_ontime_flag   SMALLINT NOT NULL CHECK (supplier_ontime_flag IN (0, 1)),
    supplier_infull_flag   SMALLINT NOT NULL CHECK (supplier_infull_flag IN (0, 1)),
    supplier_otif_flag     SMALLINT NOT NULL CHECK (supplier_otif_flag IN (0, 1)),
    supplier_lead_time_days INTEGER NOT NULL DEFAULT 0,
    lead_time_variance_days INTEGER NOT NULL DEFAULT 0,
    defect_rate_pct        DECIMAL(6,4) NOT NULL CHECK (defect_rate_pct BETWEEN 0 AND 1),
    receipt_status         VARCHAR(25) NOT NULL CHECK (receipt_status IN ('Received Complete', 'Received Late', 'Partial Received', 'Defective Order', 'In Transit'))
);

-- ============================================================================
-- 3. HIGH PERFORMANCE REPORTING INDEXES
-- ============================================================================

-- Fact Orders & Shipments Indexes
CREATE INDEX idx_fos_order_date ON core.fact_orders_shipments(order_date);
CREATE INDEX idx_fos_carrier ON core.fact_orders_shipments(carrier_id);
CREATE INDEX idx_fos_warehouse ON core.fact_orders_shipments(warehouse_id);
CREATE INDEX idx_fos_product ON core.fact_orders_shipments(product_id);
CREATE INDEX idx_fos_customer ON core.fact_orders_shipments(customer_id);
CREATE INDEX idx_fos_otif_flag ON core.fact_orders_shipments(otif_flag);
CREATE INDEX idx_fos_shipping_status ON core.fact_orders_shipments(shipping_status);

-- Fact Inventory Levels Indexes
CREATE INDEX idx_fil_snapshot_date ON core.fact_inventory_levels(snapshot_date);
CREATE INDEX idx_fil_wh_product ON core.fact_inventory_levels(warehouse_id, product_id);
CREATE INDEX idx_fil_stock_status ON core.fact_inventory_levels(stock_status);
CREATE INDEX idx_fil_stockout_risk ON core.fact_inventory_levels(stockout_risk_flag);

-- Fact Procurement POs Indexes
CREATE INDEX idx_fpo_po_date ON core.fact_procurement_pos(po_date);
CREATE INDEX idx_fpo_supplier ON core.fact_procurement_pos(supplier_id);
CREATE INDEX idx_fpo_product ON core.fact_procurement_pos(product_id);
CREATE INDEX idx_fpo_target_wh ON core.fact_procurement_pos(target_warehouse_id);
CREATE INDEX idx_fpo_otif ON core.fact_procurement_pos(supplier_otif_flag);

-- Dimensions Composite / Supporting Indexes
CREATE INDEX idx_dim_prod_category ON core.dim_products(category, abc_category);
CREATE INDEX idx_dim_supp_tier ON core.dim_suppliers(supplier_tier, country);

-- Comments on Star Schema Architecture
COMMENT ON TABLE core.fact_orders_shipments IS 'Central logistics and customer order fulfillment transactions with OTIF metrics';
COMMENT ON TABLE core.fact_inventory_levels IS 'Periodic snapshot of stock balances, days of supply, and stockout risk triggers';
COMMENT ON TABLE core.fact_procurement_pos IS 'Vendor purchase orders, lead time variance, defect rates, and vendor SLA compliance';
