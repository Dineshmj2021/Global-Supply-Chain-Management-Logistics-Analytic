-- ============================================================================
-- SUPPLY CHAIN MANAGEMENT ANALYTICS DATABASE (SupplyChainDB)
-- Script: analysis_queries.sql
-- Description: Executive-grade Business Intelligence & Supply Chain SQL Queries.
-- Topics: OTIF, Supplier Scorecards, Inventory Health, Logistics Unit Economics,
--         ABC Pareto Analysis, Warehouse Utilization, and Carrier Rankings.
-- ============================================================================

SET search_path TO reporting, core, public;

-- ============================================================================
-- QUERY 1: EXECUTIVE OTIF & SLA COMPLIANCE BY MONTH & CARRIER
-- Business Objective: Track On-Time, In-Full, and combined OTIF rates against 
-- the corporate SLA benchmark of 92.0%, including Month-over-Month change.
-- ============================================================================
WITH MonthlyCarrierStats AS (
    SELECT 
        d.month_year,
        d.year_num,
        d.month_number,
        c.carrier_name,
        c.transit_mode,
        COUNT(f.order_id) AS total_orders,
        SUM(f.ontime_flag) AS ontime_orders,
        SUM(f.infull_flag) AS infull_orders,
        SUM(f.otif_flag) AS otif_orders,
        ROUND((SUM(f.ontime_flag)::DECIMAL / COUNT(f.order_id)) * 100, 2) AS ontime_rate_pct,
        ROUND((SUM(f.infull_flag)::DECIMAL / COUNT(f.order_id)) * 100, 2) AS infull_rate_pct,
        ROUND((SUM(f.otif_flag)::DECIMAL / COUNT(f.order_id)) * 100, 2) AS otif_rate_pct
    FROM core.fact_orders_shipments f
    JOIN core.dim_date d ON f.order_date = d.date_key
    JOIN core.dim_carriers c ON f.carrier_id = c.carrier_id
    GROUP BY d.month_year, d.year_num, d.month_number, c.carrier_name, c.transit_mode
)
SELECT 
    month_year,
    carrier_name,
    transit_mode,
    total_orders,
    ontime_rate_pct,
    infull_rate_pct,
    otif_rate_pct,
    92.0 AS sla_target_pct,
    CASE 
        WHEN otif_rate_pct >= 92.0 THEN 'Target Met'
        WHEN otif_rate_pct >= 85.0 THEN 'At Risk'
        ELSE 'Critical Breach'
    END AS sla_status,
    ROUND(
        otif_rate_pct - LAG(otif_rate_pct) OVER (
            PARTITION BY carrier_name ORDER BY year_num, month_number
        ), 2
    ) AS mom_otif_change_pct
FROM MonthlyCarrierStats
ORDER BY carrier_name, year_num, month_number;


-- ============================================================================
-- QUERY 2: 360-DEGREE SUPPLIER PERFORMANCE & DEFECT SCORECARD
-- Business Objective: Evaluate vendor reliability, lead time variability,
-- defect rates, and total procurement spend to guide strategic contract renewals.
-- ============================================================================
SELECT 
    s.supplier_id,
    s.supplier_name,
    s.supplier_tier,
    s.country,
    COUNT(p.po_number) AS total_pos_issued,
    SUM(p.ordered_qty) AS total_qty_ordered,
    SUM(p.received_qty) AS total_qty_received,
    SUM(p.defect_qty) AS total_defective_qty,
    TO_CHAR(SUM(p.total_spend_usd), '$FM999,999,999') AS total_procurement_spend,
    ROUND(AVG(p.supplier_lead_time_days), 1) AS avg_actual_lead_time_days,
    s.target_lead_time_days AS agreed_lead_time_days,
    ROUND(AVG(p.lead_time_variance_days), 1) AS avg_lead_time_variance_days,
    ROUND((SUM(p.supplier_otif_flag)::DECIMAL / COUNT(p.po_number)) * 100, 2) AS supplier_otif_pct,
    ROUND((SUM(p.defect_qty)::DECIMAL / NULLIF(SUM(p.received_qty), 0)) * 100, 2) AS defect_rate_pct,
    CASE 
        WHEN (SUM(p.supplier_otif_flag)::DECIMAL / COUNT(p.po_number)) >= 0.95 
         AND (SUM(p.defect_qty)::DECIMAL / NULLIF(SUM(p.received_qty), 0)) <= 0.015 THEN 'Preferred Vendor (Tier A)'
        WHEN (SUM(p.supplier_otif_flag)::DECIMAL / COUNT(p.po_number)) >= 0.88 THEN 'Standard Compliance (Tier B)'
        ELSE 'Under Watch / Action Required (Tier C)'
    END AS vendor_standing
FROM core.fact_procurement_pos p
JOIN core.dim_suppliers s ON p.supplier_id = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name, s.supplier_tier, s.country, s.target_lead_time_days
ORDER BY SUM(p.total_spend_usd) DESC;


-- ============================================================================
-- QUERY 3: INVENTORY HEALTH & STOCKOUT RISK DETECTION
-- Business Objective: Detect SKUs with critical stockout risk (Days of Supply < 15)
-- and excessive capital tie-up (Days of Supply > 90) across distribution hubs.
-- ============================================================================
WITH LatestInventory AS (
    SELECT 
        i.snapshot_date,
        i.warehouse_id,
        w.warehouse_name,
        i.product_id,
        p.product_name,
        p.category,
        p.abc_category,
        i.stock_on_hand,
        i.safety_stock,
        i.reorder_point,
        i.average_daily_usage,
        i.days_of_supply_on_hand,
        i.inventory_value_usd,
        ROW_NUMBER() OVER (
            PARTITION BY i.warehouse_id, i.product_id 
            ORDER BY i.snapshot_date DESC
        ) AS rn
    FROM core.fact_inventory_levels i
    JOIN core.dim_warehouses w ON i.warehouse_id = w.warehouse_id
    JOIN core.dim_products p ON i.product_id = p.product_id
)
SELECT 
    warehouse_name,
    category,
    product_id,
    product_name,
    abc_category,
    stock_on_hand,
    safety_stock,
    reorder_point,
    days_of_supply_on_hand,
    TO_CHAR(inventory_value_usd, '$FM999,999.00') AS inventory_value_usd,
    CASE 
        WHEN stock_on_hand <= safety_stock THEN 'CRITICAL: Below Safety Stock'
        WHEN days_of_supply_on_hand < 15 THEN 'HIGH RISK: Impending Stockout'
        WHEN days_of_supply_on_hand BETWEEN 15 AND 60 THEN 'HEALTHY: Optimal Stock'
        WHEN days_of_supply_on_hand > 90 THEN 'WARNING: Overstocked Capital'
        ELSE 'MONITOR: Moderate Stock'
    END AS stock_health_recommendation
FROM LatestInventory
WHERE rn = 1
ORDER BY days_of_supply_on_hand ASC;


-- ============================================================================
-- QUERY 4: FREIGHT LOGISTICS ECONOMICS & UNIT COST EFFICIENCY
-- Business Objective: Compare shipping modes and carriers on cost-efficiency 
-- per unit delivered and delay penalty exposure.
-- ============================================================================
SELECT 
    c.carrier_name,
    c.transit_mode,
    COUNT(f.order_id) AS total_shipments,
    SUM(f.delivered_quantity) AS total_units_delivered,
    TO_CHAR(SUM(f.freight_cost), '$FM999,999,999') AS total_freight_spend,
    ROUND(SUM(f.freight_cost) / NULLIF(SUM(f.delivered_quantity), 0), 2) AS freight_cost_per_unit,
    ROUND(AVG(f.fulfillment_cycle_days), 1) AS avg_cycle_time_days,
    ROUND(AVG(CASE WHEN f.delivery_delay_days > 0 THEN f.delivery_delay_days ELSE NULL END), 1) AS avg_delay_days_when_late,
    ROUND((SUM(f.ontime_flag)::DECIMAL / COUNT(f.order_id)) * 100, 2) AS on_time_delivery_rate_pct,
    ROUND((SUM(f.freight_cost) / NULLIF(SUM(f.gross_revenue), 0)) * 100, 2) AS freight_pct_of_revenue
FROM core.fact_orders_shipments f
JOIN core.dim_carriers c ON f.carrier_id = c.carrier_id
GROUP BY c.carrier_name, c.transit_mode
ORDER BY freight_cost_per_unit ASC;


-- ============================================================================
-- QUERY 5: PARETO 80/20 ABC INVENTORY CLASSIFICATION
-- Business Objective: Categorize SKUs using running totals of inventory capital:
-- Class A (top 80% capital), Class B (next 15%), Class C (remaining 5%).
-- ============================================================================
WITH ProductInventoryValue AS (
    SELECT 
        p.product_id,
        p.product_name,
        p.category,
        SUM(i.inventory_value_usd) AS total_current_val
    FROM core.fact_inventory_levels i
    JOIN core.dim_products p ON i.product_id = p.product_id
    WHERE i.snapshot_date = (SELECT MAX(snapshot_date) FROM core.fact_inventory_levels)
    GROUP BY p.product_id, p.product_name, p.category
),
CumulativeCalculation AS (
    SELECT 
        product_id,
        product_name,
        category,
        total_current_val,
        SUM(total_current_val) OVER () AS total_portfolio_val,
        SUM(total_current_val) OVER (
            ORDER BY total_current_val DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_cum_val
    FROM ProductInventoryValue
)
SELECT 
    product_id,
    product_name,
    category,
    TO_CHAR(total_current_val, '$FM999,999.00') AS current_inventory_val,
    ROUND((running_cum_val / total_portfolio_val) * 100, 2) AS cumulative_pct_of_capital,
    CASE 
        WHEN (running_cum_val / total_portfolio_val) <= 0.80 THEN 'Class A (High Value / Strict Control)'
        WHEN (running_cum_val / total_portfolio_val) <= 0.95 THEN 'Class B (Moderate Value)'
        ELSE 'Class C (Low Value / High Volume)'
    END AS pareto_abc_tier
FROM CumulativeCalculation
ORDER BY total_current_val DESC;


-- ============================================================================
-- QUERY 6: PROFITABILITY & MARGIN WATERFALL BY PRODUCT CATEGORY
-- Business Objective: Determine gross and net profit contribution after deducting
-- COGS and freight distribution expenses across categories.
-- ============================================================================
SELECT 
    p.category,
    COUNT(f.order_id) AS total_orders_fulfilled,
    TO_CHAR(SUM(f.gross_revenue), '$FM999,999,999') AS total_gross_revenue,
    TO_CHAR(SUM(f.cogs), '$FM999,999,999') AS total_cogs,
    TO_CHAR(SUM(f.gross_profit), '$FM999,999,999') AS total_gross_profit,
    ROUND((SUM(f.gross_profit) / NULLIF(SUM(f.gross_revenue), 0)) * 100, 2) AS gross_margin_pct,
    TO_CHAR(SUM(f.freight_cost), '$FM999,999,999') AS total_freight_logistics_cost,
    TO_CHAR(SUM(f.net_margin), '$FM999,999,999') AS net_contribution_margin,
    ROUND((SUM(f.net_margin) / NULLIF(SUM(f.gross_revenue), 0)) * 100, 2) AS net_margin_pct
FROM core.fact_orders_shipments f
JOIN core.dim_products p ON f.product_id = p.product_id
GROUP BY p.category
ORDER BY SUM(f.gross_revenue) DESC;


-- ============================================================================
-- QUERY 7: WAREHOUSE CAPACITY UTILIZATION & OPERATIONAL STRESS
-- Business Objective: Identify distribution centers exceeding the 85% safe
-- capacity ceiling to prevent warehouse congestion and throughput delays.
-- ============================================================================
WITH CurrentWarehouseOccupancy AS (
    SELECT 
        w.warehouse_id,
        w.warehouse_name,
        w.region,
        w.max_capacity_units,
        SUM(i.stock_on_hand) AS total_units_stored,
        SUM(i.inventory_value_usd) AS total_capital_stored
    FROM core.fact_inventory_levels i
    JOIN core.dim_warehouses w ON i.warehouse_id = w.warehouse_id
    WHERE i.snapshot_date = (SELECT MAX(snapshot_date) FROM core.fact_inventory_levels)
    GROUP BY w.warehouse_id, w.warehouse_name, w.region, w.max_capacity_units
)
SELECT 
    warehouse_id,
    warehouse_name,
    region,
    max_capacity_units,
    total_units_stored,
    (max_capacity_units - total_units_stored) AS remaining_headroom_units,
    ROUND((total_units_stored::DECIMAL / max_capacity_units) * 100, 2) AS capacity_utilization_pct,
    TO_CHAR(total_capital_stored, '$FM999,999,999') AS total_capital_stored,
    CASE 
        WHEN (total_units_stored::DECIMAL / max_capacity_units) >= 0.90 THEN 'CRITICAL: Severe Overcrowding (>90%)'
        WHEN (total_units_stored::DECIMAL / max_capacity_units) >= 0.75 THEN 'WARNING: High Utilization (75-90%)'
        WHEN (total_units_stored::DECIMAL / max_capacity_units) >= 0.50 THEN 'OPTIMAL: Balanced (50-75%)'
        ELSE 'UNDERUTILIZED: Idle Footprint (<50%)'
    END AS operational_status
FROM CurrentWarehouseOccupancy
ORDER BY capacity_utilization_pct DESC;


-- ============================================================================
-- QUERY 8: ROOT CAUSE INVESTIGATION OF ORDER RETURNS & REVENUE LOSS
-- Business Objective: Dissect return reasons, associated revenue erosion,
-- and identify problematic product categories driving customer dissatisfaction.
-- ============================================================================
SELECT 
    f.return_reason,
    p.category AS product_category,
    COUNT(f.order_id) AS returned_orders_count,
    SUM(f.order_quantity) AS returned_units,
    TO_CHAR(SUM(f.gross_revenue), '$FM999,999,999') AS revenue_refunded_usd,
    TO_CHAR(SUM(f.freight_cost), '$FM999,999,999') AS lost_freight_expense_usd,
    ROUND((COUNT(f.order_id)::DECIMAL / SUM(COUNT(f.order_id)) OVER ()) * 100, 2) AS pct_of_all_returns
FROM core.fact_orders_shipments f
JOIN core.dim_products p ON f.product_id = p.product_id
WHERE f.return_flag = 1
GROUP BY f.return_reason, p.category
ORDER BY SUM(f.gross_revenue) DESC;


-- ============================================================================
-- QUERY 9: ROLLING 3-MONTH PROCUREMENT SPEND & MOM GROWTH
-- Business Objective: Analyze macro procurement cash burn rate over time
-- using window aggregation frames.
-- ============================================================================
WITH MonthlyProcurement AS (
    SELECT 
        d.year_num,
        d.month_number,
        d.month_year,
        SUM(p.total_spend_usd) AS monthly_spend
    FROM core.fact_procurement_pos p
    JOIN core.dim_date d ON p.po_date = d.date_key
    GROUP BY d.year_num, d.month_number, d.month_year
)
SELECT 
    month_year,
    TO_CHAR(monthly_spend, '$FM999,999,999') AS monthly_spend,
    ROUND(
        ((monthly_spend - LAG(monthly_spend) OVER (ORDER BY year_num, month_number)) / 
        NULLIF(LAG(monthly_spend) OVER (ORDER BY year_num, month_number), 0)) * 100, 2
    ) AS mom_spend_growth_pct,
    TO_CHAR(
        AVG(monthly_spend) OVER (
            ORDER BY year_num, month_number 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), '$FM999,999,999'
    ) AS rolling_3month_avg_spend
FROM MonthlyProcurement
ORDER BY year_num, month_number;


-- ============================================================================
-- QUERY 10: MULTI-CRITERIA CARRIER COMPOSITE RANKING
-- Business Objective: Rank carriers using a weighted scorecard:
-- 50% OTIF Reliability + 30% Cost Efficiency + 20% Speed.
-- ============================================================================
WITH CarrierMetrics AS (
    SELECT 
        c.carrier_id,
        c.carrier_name,
        c.transit_mode,
        ROUND((SUM(f.otif_flag)::DECIMAL / COUNT(f.order_id)) * 100, 2) AS otif_pct,
        ROUND(SUM(f.freight_cost) / NULLIF(SUM(f.delivered_quantity), 0), 2) AS cost_per_unit,
        ROUND(AVG(f.fulfillment_cycle_days), 1) AS avg_cycle_days
    FROM core.fact_orders_shipments f
    JOIN core.dim_carriers c ON f.carrier_id = c.carrier_id
    GROUP BY c.carrier_id, c.carrier_name, c.transit_mode
),
NormalizedScores AS (
    SELECT 
        carrier_id,
        carrier_name,
        transit_mode,
        otif_pct,
        cost_per_unit,
        avg_cycle_days,
        -- Normalized sub-scores from 0 to 100
        PERCENT_RANK() OVER (ORDER BY otif_pct ASC) * 100 AS otif_score,
        PERCENT_RANK() OVER (ORDER BY cost_per_unit DESC) * 100 AS cost_score, -- lower cost is better
        PERCENT_RANK() OVER (ORDER BY avg_cycle_days DESC) * 100 AS speed_score  -- lower cycle time is better
    FROM CarrierMetrics
)
SELECT 
    carrier_name,
    transit_mode,
    otif_pct,
    cost_per_unit,
    avg_cycle_days,
    ROUND((0.50 * otif_score + 0.30 * cost_score + 0.20 * speed_score)::DECIMAL, 1) AS composite_efficiency_index,
    DENSE_RANK() OVER (
        ORDER BY (0.50 * otif_score + 0.30 * cost_score + 0.20 * speed_score) DESC
    ) AS overall_carrier_rank
FROM NormalizedScores
ORDER BY overall_carrier_rank;
