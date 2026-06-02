# Final Project — Fitness Club Database

## Domain Description
A **Fitness Club** management system covering member registration, membership plan
subscriptions, group class scheduling, trainer assignment, room allocation, and
attendance tracking. The `class_attendance` junction table resolves the many-to-many
relationship between members and classes.

## Database & Schema
| Setting  | Value                   |
|----------|-------------------------|
| Database | `fitness_club_db`       |
| Schema   | `fitness_club_schema`   |

## Run Instructions
1. Connect to `postgres` default database as superuser.
2. Run the first block (DO $$ CREATE DATABASE $$).
3. Reconnect to `fitness_club_db`.
4. Run `02_final.sql` top to bottom — fully re-runnable.

```bash
psql -U postgres -d fitness_club_db -f 02_final.sql
```

## Script Structure
| Part | Contents                                              | Points |
|------|-------------------------------------------------------|--------|
| 0    | CREATE DATABASE + SCHEMA                              | —      |
| 1    | DROP TABLE IF EXISTS (correct FK order)               | —      |
| 2    | CREATE TABLE x7 with PKs, FKs, CHECKs, GENERATED     | 8 pts  |
| 3    | ALTER TABLE x5 (ADD COLUMN, ALTER TYPE, ADD CONSTRAINT, SET DEFAULT, RENAME) | 3 pts |
| 4    | TRUNCATE + INSERT (multi-row VALUES + INSERT…SELECT)  | 7 pts  |
| 5    | UPDATE x2 (simple + FROM another table)               | 2 pts  |
| 6    | BEGIN / DELETE / ROLLBACK with RETURNING              | 3 pts  |
| 7    | DROP ROLE + CREATE ROLE x2 + GRANT + REVOKE           | 3 pts  |

## Deliverables
| File           | Contents                                    |
|----------------|---------------------------------------------|
| `01_model.pdf` | Conceptual ERD, Logical schema, 3NF, Physical schema diagram |
| `02_final.sql` | Complete SQL script                         |
| `README.md`    | This file                                   |
