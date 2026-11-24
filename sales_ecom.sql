-- 1. Warehouses Table
CREATE TABLE warehouses (
    warehouse_id VARCHAR(10) PRIMARY KEY,
    city VARCHAR(50) NOT NULL,
    region VARCHAR(20) NOT NULL,
    monthly_capacity INT NOT NULL
);

-- 2. Suppliers Table
CREATE TABLE suppliers (
    supplier_id VARCHAR(10) PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    contract_lead_days INT NOT NULL
);

-- 3. Products Table
CREATE TABLE products (
    product_id VARCHAR(10) PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    unit_cost NUMERIC(10, 2) NOT NULL,
    reorder_level INT NOT NULL,
    supplier_id VARCHAR(10) REFERENCES suppliers(supplier_id)
);

-- 4. Shipments Table
CREATE TABLE shipments (
    shipment_id VARCHAR(15) PRIMARY KEY,
    order_date DATE NOT NULL,
    dispatch_date DATE,
    delivery_date DATE,
    promised_date DATE NOT NULL,
    warehouse_id VARCHAR(10) REFERENCES warehouses(warehouse_id),
    product_id VARCHAR(10) REFERENCES products(product_id),
    quantity INT NOT NULL,
    shipping_cost NUMERIC(10, 2) NOT NULL,
    delivery_status VARCHAR(30) NOT NULL,
    is_defective BOOLEAN NOT NULL
);


---join to find the delivered 
select * from shipments;
select * from shipments s 
join warehouses w
on s.warehouse_id = w.warehouse_id
where s.delivery_status = 'Delivered';

---join to find the count 
select w.city,w.region,count(*) from warehouses w 
join shipments s 
on w.warehouse_id = s.warehouse_id
Group by w.city,w.region;

---find the on time delivered products 
SELECT 
    w.city,
    w.region,
    COUNT(*) AS total_delivered,
    SUM(CASE WHEN s.delivery_date <= s.promised_date THEN 1 ELSE 0 END) AS on_time_shipments,
    ROUND(100.0 * SUM(CASE WHEN s.delivery_date <= s.promised_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS otd_pct
FROM warehouses w
JOIN shipments s 
    ON w.warehouse_id = s.warehouse_id
WHERE s.delivery_status = 'Delivered'
GROUP BY w.city, w.region
ORDER BY otd_pct ASC;


---  to find the total transit time and avg dispatch time  
select w.city,AVG(s.dispatch_date - s.order_date) as awpd,
AVG(s.delivery_date - s.dispatch_date) as Avg_Courier_Transit_Days,
AVG(s.delivery_date - s.order_date) as avg_total_tat
from warehouses w
join shipments s 
on w.warehouse_id = s.warehouse_id
where s.delivery_status = 'Delivered' and s.dispatch_date >= s.order_date
Group by w.city
order by avg_total_tat desc;



---find the highest defect supplier and highest defective value incured by the company 
WITH supplier_metrics AS (
    SELECT 
        s.supplier_name,
        s.category,
        COUNT(*) AS total_shipments,
        SUM(CASE WHEN s1.is_defective = TRUE THEN 1 ELSE 0 END) AS defective_shipments,
        ROUND(100.0 * SUM(CASE WHEN s1.is_defective = TRUE THEN 1 ELSE 0 END) / COUNT(*), 2) AS defect_rate_pct,
        ROUND(SUM(CASE WHEN s1.is_defective = TRUE THEN s1.quantity * p.unit_cost ELSE 0 END), 2) AS defective_value_inr
    FROM suppliers s
    JOIN products p
        ON s.supplier_id = p.supplier_id
    JOIN shipments s1
        ON s1.product_id = p.product_id
    WHERE s1.delivery_status = 'Delivered'
    GROUP BY s.supplier_name, s.category
)
SELECT 
    *,
    DENSE_RANK() OVER (ORDER BY defect_rate_pct DESC) AS quality_risk_rank
FROM supplier_metrics
ORDER BY quality_risk_rank ASC;

---Month-over-Month (MoM) Cost & Volume Trend
with monthly_trend as (
select DATE_TRUNC('month', order_date)::DATE AS order_month, Count(*) as total_shipments,Round(sum(shipping_cost),2) total_shipping_cost from shipments
WHERE delivery_status != 'Cancelled'
Group by order_month
)
select order_month,total_shipments,total_shipping_cost,
LAG(total_shipping_cost) OVER (ORDER BY order_month) AS prev_month_cost,
ROUND(100.0 * (total_shipping_cost - LAG(total_shipping_cost) OVER (ORDER BY order_month)) / LAG(total_shipping_cost) OVER (ORDER BY order_month), 2) AS mom_cost_change_pct
from monthly_trend
order by order_month asc;




CREATE OR REPLACE VIEW vw_supply_chain_master AS
SELECT 
    s.shipment_id,
    s.order_date,
    s.dispatch_date,
    s.delivery_date,
    s.promised_date,
    s.delivery_status,
    s.quantity,
    s.shipping_cost,
    s.is_defective,
    
    -- Warehouse details
    w.warehouse_id,
    w.city AS warehouse_city,
    w.region,
    w.monthly_capacity,
    
    -- Product & Supplier details
    p.product_id,
    p.product_name,
    p.category,
    p.unit_cost,
    (s.quantity * p.unit_cost) AS order_value_inr,
    sup.supplier_id,
    sup.supplier_name,
    sup.contract_lead_days,
    
    -- Pre-calculated Operational Flags & TAT Metrics
    CASE 
        WHEN s.delivery_status = 'Delivered' AND s.delivery_date <= s.promised_date THEN 1 
        ELSE 0 
    END AS is_on_time,
    
    CASE 
        WHEN s.dispatch_date < s.order_date THEN TRUE 
        ELSE FALSE 
    END AS is_date_anomaly,
    
    CASE 
        WHEN s.delivery_status = 'Delivered' AND s.dispatch_date >= s.order_date 
        THEN (s.dispatch_date - s.order_date) 
    END AS processing_days,
    
    CASE 
        WHEN s.delivery_status = 'Delivered' AND s.dispatch_date >= s.order_date 
        THEN (s.delivery_date - s.dispatch_date) 
    END AS transit_days,
    
    CASE 
        WHEN s.delivery_status = 'Delivered' AND s.dispatch_date >= s.order_date 
        THEN (s.delivery_date - s.order_date) 
    END AS total_tat_days

FROM shipments s
JOIN warehouses w ON s.warehouse_id = w.warehouse_id
JOIN products p ON s.product_id = p.product_id
JOIN suppliers sup ON p.supplier_id = sup.supplier_id;

SELECT * FROM vw_supply_chain_master LIMIT 5;

















































