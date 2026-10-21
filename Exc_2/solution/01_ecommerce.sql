\set ON_ERROR_STOP on
\pset pager off
\timing on

\echo A - Order with the highest price per unit (including ties)
SELECT *
FROM orders
WHERE price_per_unit = (SELECT MAX(price_per_unit) FROM orders)
ORDER BY id;

\echo B - Top three categories by total quantity sold
SELECT product_category, SUM(quantity) AS total_quantity
FROM orders
GROUP BY product_category
ORDER BY total_quantity DESC, product_category
LIMIT 3;

\echo C - Revenue per category
SELECT product_category, SUM(price_per_unit * quantity) AS total_revenue
FROM orders
GROUP BY product_category
ORDER BY total_revenue DESC, product_category;

\echo D - Top five customer names by spending, with their order counts
SELECT customer_name,
       COUNT(*) AS order_count,
       SUM(price_per_unit * quantity) AS total_spending
FROM orders
GROUP BY customer_name
ORDER BY total_spending DESC, customer_name
LIMIT 5;

\echo E - Check how many different customer names the generator produced
SELECT COUNT(DISTINCT customer_name) AS different_names,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT customer_name), 2)
           AS average_orders_per_name
FROM orders;
