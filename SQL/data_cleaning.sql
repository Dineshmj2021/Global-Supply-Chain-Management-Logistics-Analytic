-- ============================================================================
-- SUPPLY CHAIN MANAGEMENT ANALYTICS DATABASE (SupplyChainDB)
-- Script: data_cleaning.sql
-- Description: Production-grade data cleansing, anomaly detection, deduplication,
--              business logic validation, and audit view creation.
-- ============================================================================

SET search_path TO staging, core, reporting, public;

-- ============================================================================
-- 1. DATA AUDITING & ANOMALY DETECTION
-- ============================================================================

-- Check 1.1: Identify Orders with Missing Delivery Dates despite being Delivered
SELECT 
    order_id,
    order_date,
    ship_date,
    promised_delivery_date,
    actual_delivery_date,
    shipping_status
FROM core.fact_orders_shipments
WHERE shipping_status IN ('Delivered On-Time', 'Delivered Late')
  AND actual_delivery_date IS NULL;

-- Check 1.2: Identify Negative or Outlier Freight Costs
SELECT 
    order_id,
    order_quantity,
    gross_revenue,
    freight_cost,
    ROUND((freight_cost / NULLIF(gross_revenue, 0)) * 100, 2) AS freight_pct_of_rev
FROM core.fact_orders_shipments
WHERE freight_cost <= 0 
   OR freight_cost > gross_revenue;

-- Check 1.3: Identify Duplicate Purchase Orders in Raw Staging
WITH RankedPOs AS (
    SELECT 
        po_number,
        po_date,
        supplier_id,
        product_id,
        ROW_NUMBER() OVER (
            PARTITION BY po_number 
            ORDER BY po_date DESC
        ) AS row_num
    FROM core.fact_procurement_pos
)
SELECT * 
FROM RankedPOs 
WHERE row_num > 1;

-- Check 1.4: Identify Orphaned Product Keys in Orders
SELECT DISTINCT 
    f.product_id,
    COUNT(f.order_id) AS orphaned_orders_count
FROM core.fact_orders_shipments f
LEFT JOIN core.dim_products p ON f.product_id = p.product_id
WHERE p.product_id IS NULL
GROUP BY f.product_id;

-- ============================================================================
-- 2. DATA CLEANSING & TRANSFORMATION PROCEDURES
-- ============================================================================

-- Step 2.1: Trim Whitespace and Standardize Casing across Dimensions
UPDATE core.dim_carriers
SET carrier_id   = UPPER(TRIM(carrier_id)),
    carrier_name = TRIM(carrier_name),
    transit_mode = TRIM(transit_mode);

UPDATE core.dim_products
SET product_id   = UPPER(TRIM(product_id)),
    product_name = TRIM(product_name),
    category     = TRIM(category),
    abc_category = UPPER(TRIM(abc_category));

UPDATE core.dim_warehouses
SET warehouse_id = UPPER(TRIM(warehouse_id)),
    warehouse_name = TRIM(warehouse_name),
    region       = TRIM(region);

-- Step 2.2: Clean and Normalize Fact Orders & Shipments
-- Fix null return reasons, sanitize status, recalculate OTIF flags
UPDATE core.fact_orders_shipments
SET 
    return_reason = CASE 
        WHEN return_flag = 0 THEN 'None'
        WHEN return_reason IS NULL OR TRIM(return_reason) = '' THEN 'Unspecified'
        ELSE TRIM(return_reason)
    END,
    shipping_status = CASE 
        WHEN return_flag = 1 THEN 'Returned'
        WHEN actual_delivery_date IS NULL THEN 'In Transit'
        WHEN actual_delivery_date <= promised_delivery_date THEN 'Delivered On-Time'
        ELSE 'Delivered Late'
    END,
    ontime_flag = CASE 
        WHEN actual_delivery_date IS NOT NULL AND actual_delivery_date <= promised_delivery_date THEN 1 
        ELSE 0 
    END,
    infull_flag = CASE 
        WHEN delivered_quantity >= order_quantity THEN 1 
        ELSE 0 
    END;

-- Re-compute OTIF flag strictly (Both On-Time AND In-Full)
UPDATE core.fact_orders_shipments
SET otif_flag = CASE 
    WHEN ontime_flag = 1 AND infull_flag = 1 THEN 1 
    ELSE 0 
END;

-- Compute accurate delay days and fulfillment cycle days
UPDATE core.fact_orders_shipments
SET delivery_delay_days = CASE 
        WHEN actual_delivery_date IS NOT NULL AND actual_delivery_date > promised_delivery_date 
        THEN (actual_delivery_date - promised_delivery_date)
        ELSE 0 
    END,
    fulfillment_cycle_days = CASE 
        WHEN actual_delivery_date IS NOT NULL 
        THEN (actual_delivery_date - order_date)
        ELSE (CURRENT_DATE - order_date)
    END;

-- Step 2.3: Clean and Normalize Procurement POs
UPDATE core.fact_procurement_pos
SET 
    supplier_ontime_flag = CASE 
        WHEN actual_receipt_date IS NOT NULL AND actual_receipt_date <= promised_receipt_date THEN 1 
        ELSE 0 
    END,
    supplier_infull_flag = CASE 
        WHEN received_qty >= ordered_qty THEN 1 
        ELSE 0 
    END,
    lead_time_variance_days = CASE 
        WHEN actual_receipt_date IS NOT NULL 
        THEN (actual_receipt_date - promised_receipt_date)
        ELSE 0 
    END,
    defect_rate_pct = CASE 
        WHEN received_qty > 0 THEN ROUND((defect_qty::DECIMAL / received_qty::DECIMAL), 4)
        ELSE 0.0000 
    END;

UPDATE core.fact_procurement_pos
SET supplier_otif_flag = CASE 
    WHEN supplier_ontime_flag = 1 AND supplier_infull_flag = 1 THEN 1 
    ELSE 0 
END;

-- ============================================================================
-- 3. AUDIT & QUALITY VALIDATION VIEWS
-- ============================================================================

-- View 3.1: Data Quality Scorecard Summary
CREATE OR REPLACE VIEW reporting.vw_data_quality_audit AS
SELECT 
    'Orders & Shipments' AS table_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN actual_delivery_date IS NULL AND shipping_status = 'Delivered On-Time' THEN 1 ELSE 0 END) AS invalid_delivery_dates,
    SUM(CASE WHEN delivered_quantity > order_quantity * 1.5 THEN 1 ELSE 0 END) AS over_delivery_anomalies,
    SUM(CASE WHEN gross_profit < 0 THEN 1 ELSE 0 END) AS negative_margin_orders,
    SUM(CASE WHEN otif_flag NOT IN (0, 1) THEN 1 ELSE 0 END) AS corrupted_otif_flags,
    ROUND((SUM(CASE WHEN otif_flag = 1 THEN 1 ELSE 0 END)::DECIMAL / COUNT(*)) * 100, 2) AS clean_otif_compliance_pct
FROM core.fact_orders_shipments
UNION ALL
SELECT 
    'Procurement POs' AS table_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN actual_receipt_date IS NULL AND receipt_status = 'Received Complete' THEN 1 ELSE 0 END) AS invalid_delivery_dates,
    SUM(CASE WHEN defect_qty > received_qty THEN 1 ELSE 0 END) AS over_delivery_anomalies,
    SUM(CASE WHEN total_spend_usd <= 0 THEN 1 ELSE 0 END) AS negative_margin_orders,
    SUM(CASE WHEN supplier_otif_flag NOT IN (0, 1) THEN 1 ELSE 0 END) AS corrupted_otif_flags,
    ROUND((SUM(CASE WHEN supplier_otif_flag = 1 THEN 1 ELSE 0 END)::DECIMAL / COUNT(*)) * 100, 2) AS clean_otif_compliance_pct
FROM core.fact_procurement_pos;

-- View 3.2: Clean Orders Ready for Power BI Consumption
CREATE OR REPLACE VIEW reporting.vw_clean_orders_shipments AS
SELECT 
    o.order_id,
    o.order_date,
    o.ship_date,
    o.promised_delivery_date,
    o.actual_delivery_date,
    o.customer_id,
    c.customer_name,
    c.customer_segment,
    o.customer_country,
    c.region AS customer_region,
    o.product_id,
    p.product_name,
    p.category AS product_category,
    p.abc_category,
    o.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    o.carrier_id,
    cr.carrier_name,
    cr.transit_mode,
    o.order_priority,
    o.order_quantity,
    o.delivered_quantity,
    o.unit_sale_price,
    o.unit_cost,
    o.gross_revenue,
    o.cogs,
    o.gross_profit,
    o.freight_cost,
    o.net_margin,
    o.ontime_flag,
    o.infull_flag,
    o.otif_flag,
    o.delivery_delay_days,
    o.fulfillment_cycle_days,
    o.return_flag,
    o.return_reason,
    o.shipping_status
FROM core.fact_orders_shipments o
JOIN core.dim_customers c ON o.customer_id = c.customer_id
JOIN core.dim_products p ON o.product_id = p.product_id
JOIN core.dim_warehouses w ON o.warehouse_id = w.warehouse_id
JOIN core.dim_carriers cr ON o.carrier_id = cr.carrier_id;

-- Verify Audit View
SELECT * FROM reporting.vw_data_quality_audit;
