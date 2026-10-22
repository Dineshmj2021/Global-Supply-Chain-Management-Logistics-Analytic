-- ============================================================================
-- SUPPLY CHAIN MANAGEMENT ANALYTICS DATABASE (SupplyChainDB)
-- Script: database_creation.sql
-- Description: Creates the analytical database, schemas, and configurations.
-- Compatible with: PostgreSQL, Microsoft SQL Server, and MySQL 8.0+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Section 1: Database Creation (Microsoft SQL Server / PostgreSQL syntax)
-- ----------------------------------------------------------------------------

-- SQL Server Syntax:
/*
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'SupplyChainDB')
BEGIN
    CREATE DATABASE SupplyChainDB;
END;
GO
USE SupplyChainDB;
GO
*/

-- PostgreSQL Syntax:
-- DROP DATABASE IF EXISTS supply_chain_db;
CREATE DATABASE supply_chain_db
    WITH 
    ENCODING = 'UTF8'
    LC_COLLATE = 'English_United States.1252'
    LC_CTYPE = 'English_United States.1252'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

\c supply_chain_db;

-- ----------------------------------------------------------------------------
-- Section 2: Schema Creation (Logical Grouping)
-- ----------------------------------------------------------------------------
-- Staging schema: raw ingested files before transformations
CREATE SCHEMA IF NOT EXISTS staging;

-- Core analytical schema: Kimball Star Schema (Dimensions & Facts)
CREATE SCHEMA IF NOT EXISTS core;

-- Analytics / Reporting schema: Aggregated views & marts for Power BI consumption
CREATE SCHEMA IF NOT EXISTS reporting;

-- ----------------------------------------------------------------------------
-- Section 3: Performance & Session Configurations
-- ----------------------------------------------------------------------------
-- Setting work memory and search path for session
SET search_path TO reporting, core, staging, public;

COMMENT ON SCHEMA core IS 'Enterprise Star Schema Dimension and Fact tables';
COMMENT ON SCHEMA staging IS 'Staging area for raw CSV ingest and ETL processing';
COMMENT ON SCHEMA reporting IS 'Optimized analytical views tailored for Power BI DirectQuery / Import';

-- Verification
SELECT 
    current_database() AS active_database,
    current_schema() AS active_schema,
    current_timestamp AS setup_timestamp;
