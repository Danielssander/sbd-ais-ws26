\set ON_ERROR_STOP on
\pset pager off
\timing on

-- Run in an exercise database. This replaces the exercise tables.
DROP TABLE IF EXISTS people_50k, people_100k, people_200k;
DROP TABLE IF EXISTS people_big, orders;

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    product_category TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price_per_unit NUMERIC(10, 2) NOT NULL CHECK (price_per_unit >= 0),
    order_date DATE NOT NULL,
    country TEXT NOT NULL
);

\copy orders(customer_name, product_category, quantity, price_per_unit, order_date, country) FROM '/data/orders_1M.csv' DELIMITER ',' CSV HEADER

CREATE TABLE people_big (
    id SERIAL PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    department TEXT,
    salary INTEGER,
    country TEXT
);

\copy people_big(first_name, last_name, gender, department, salary, country) FROM '/data/people_1M.csv' DELIMITER ',' CSV HEADER

ANALYZE orders;
ANALYZE people_big;

SELECT COUNT(*) AS order_count FROM orders;
SELECT COUNT(*) AS people_count FROM people_big;
