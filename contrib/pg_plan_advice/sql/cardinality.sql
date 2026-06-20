LOAD 'pg_plan_advice';
SET max_parallel_workers_per_gather = 0;

CREATE TABLE ca_t1 (id integer primary key, val integer)
	WITH (autovacuum_enabled = false);
INSERT INTO ca_t1 SELECT g, g FROM generate_series(1, 1000) g;
VACUUM ANALYZE ca_t1;

CREATE TABLE ca_t2 (id integer primary key, val integer)
	WITH (autovacuum_enabled = false);
INSERT INTO ca_t2 SELECT g, g FROM generate_series(1, 100) g;
VACUUM ANALYZE ca_t2;

CREATE TABLE ca_t3 (id integer primary key, val integer)
	WITH (autovacuum_enabled = false);
INSERT INTO ca_t3 SELECT g, g FROM generate_series(1, 10) g;
VACUUM ANALYZE ca_t3;

-- Baseline row estimates without advice
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1 JOIN ca_t2 t2 ON t1.val = t2.val JOIN ca_t3 t3 ON t2.val = t3.val;

-- Baserel: add constant to one table's scan estimate
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY(t1 + 1000)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1;
COMMIT;

-- Multi-baserel: multiply each listed scan estimate
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY(t1 t2 * 2)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1 JOIN ca_t2 t2 ON t1.val = t2.val;
COMMIT;

-- Join-level: multiply lowest join containing both relations
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY((t1 t2) * 2)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1 JOIN ca_t2 t2 ON t1.val = t2.val;
COMMIT;

-- Three-way join: adjustment at top join only
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY((t1 t2 t3) * 0.5)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1 JOIN ca_t2 t2 ON t1.val = t2.val JOIN ca_t3 t3 ON t2.val = t3.val;
COMMIT;

-- Set estimate exactly (clamped to at least 1)
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY(t3 = 1)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t3 t3;
COMMIT;

-- Floating-point multiplier
BEGIN;
SET LOCAL pg_plan_advice.advice = 'CARDINALITY((t1 t2) * 0.7)';
EXPLAIN (COSTS OFF)
SELECT * FROM ca_t1 t1 JOIN ca_t2 t2 ON t1.val = t2.val;
COMMIT;

-- Syntax error: division by zero
SET pg_plan_advice.advice = 'CARDINALITY(t1 / 0)';

-- Syntax error: join target needs at least two relations
SET pg_plan_advice.advice = 'CARDINALITY((t1) * 2)';

-- Valid parse check for advice GUC
SET pg_plan_advice.advice = 'CARDINALITY(t1 + 2) CARDINALITY((t1 t2) * 2)';
RESET pg_plan_advice.advice;
