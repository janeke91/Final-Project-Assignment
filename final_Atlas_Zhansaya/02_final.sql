-- =============================================================
--  FINAL PROJECT: Fitness Club Database
--  Database : fitness_club
--  Schema   : fitness_club_db
--  Author   : (your name)
--  Run      : psql -U postgres -d fitness_club -f 02_final.sql
-- =============================================================


-- =============================================================
--  PART 1: DATABASE + SCHEMA SETUP
-- =============================================================

-- create the database manually before running this script:
--   CREATE DATABASE fitness_club;
-- then connect to it: \c fitness_club

create schema if not exists fitness_club_db;
set search_path to fitness_club_db;


-- =============================================================
--  PART 2: CREATE — DROP (correct FK dependency order)
-- =============================================================

drop table if exists fitness_club_db.payments            cascade;
drop table if exists fitness_club_db.schedule_enrollment cascade;
drop table if exists fitness_club_db.schedule            cascade;
drop table if exists fitness_club_db.facilities          cascade;
drop table if exists fitness_club_db.classes             cascade;
drop table if exists fitness_club_db.instructors         cascade;
drop table if exists fitness_club_db.members             cascade;
drop table if exists fitness_club_db.membership_types    cascade;


-- =============================================================
--  PART 2: CREATE — TABLE DEFINITIONS + CONSTRAINTS
-- =============================================================

create table if not exists membership_types (
    membership_type_id  serial          primary key,
    name                varchar(50)     not null unique,                          -- UNIQUE natural key
    duration_months     int             not null check (duration_months > 0),     -- CHECK: positive duration
    price               numeric(10,2)   not null check (price >= 0),              -- CHECK: non-negative money
    access_level        varchar(50)     not null check (access_level in ('VIP', 'Standard', 'Basic')),  -- CHECK: enum
    is_active           boolean         not null default true,                    -- DEFAULT: new plans are active
    record_ts           date            not null default current_date
);

create table if not exists members (
    member_id           serial          primary key,
    first_name          varchar(50)     not null,
    last_name           varchar(50)     not null,
    email               varchar(100)    not null unique,                          -- UNIQUE natural key
    phone               varchar(20)     not null,                                 -- NOT NULL on non-obvious column
    date_of_birth       date            not null,
    membership_type_id  int             not null references membership_types(membership_type_id)
                                            on delete restrict,
    joined_date         date            not null check (joined_date > date '2026-01-01'),  -- CHECK: date after 2026
    record_ts           date            not null default current_date
);

create table if not exists instructors (
    instructor_id       serial          primary key,
    first_name          varchar(50)     not null,
    last_name           varchar(50)     not null,
    specialization      varchar(50)     not null check (specialization in ('Yoga', 'Cardio', 'MMA', 'Gym', 'Pilates')),  -- CHECK: enum
    hourly_rate         numeric(10,2)   not null check (hourly_rate >= 0),        -- CHECK: non-negative
    record_ts           date            not null default current_date
);

create table if not exists classes (
    class_id            serial          primary key,
    name                varchar(100)    not null unique,
    description         text,
    category            varchar(50)     not null check (category in ('Yoga', 'Cardio', 'Strength', 'Combat', 'Wellness')),
    record_ts           date            not null default current_date
);

create table if not exists facilities (
    facility_id         serial          primary key,
    name                varchar(50)     not null,
    capacity            int             not null check (capacity >= 0),           -- CHECK: non-negative
    location_description varchar(100),
    record_ts           date            not null default current_date
);

create table if not exists schedule (
    schedule_id         serial          primary key,
    class_id            int             not null references classes(class_id)
                                            on delete restrict,
    instructor_id       int             not null references instructors(instructor_id)
                                            on delete restrict,
    facility_id         int             not null references facilities(facility_id)
                                            on delete restrict,
    session_date        date            not null check (session_date > date '2026-01-01'),
    duration_minutes    int             not null check (duration_minutes > 0),
    duration_hours      numeric(5,2)    generated always as (duration_minutes / 60.0) stored,  -- GENERATED column
    record_ts           date            not null default current_date
);

create table if not exists schedule_enrollment (
    member_id           int             not null references members(member_id)
                                            on delete cascade,
    schedule_id         int             not null references schedule(schedule_id)
                                            on delete cascade,
    primary key (member_id, schedule_id),
    enrolled_at         timestamp       not null default current_timestamp,
    record_ts           date            not null default current_date
);

create table if not exists payments (
    payment_id          serial          primary key,
    amount              numeric(10,2)   not null check (amount >= 0),
    payment_date        timestamp       not null default current_timestamp,
    payment_method      varchar(30)     not null check (payment_method in ('Cash', 'Card', 'Transfer')),
    member_id           int             not null references members(member_id)
                                            on delete restrict,
    note                text,
    record_ts           date            not null default current_date,
    check (payment_date > '2026-01-01 00:00:00')                                 -- CHECK: date after 2026
);


-- =============================================================
--  PART 3: ALTER TABLE (5 meaningful operations)
-- =============================================================

-- add a contact emergency phone column that was overlooked during initial design
alter table members add column emergency_contact varchar(20) default 'N/A';

-- widen the phone column: international numbers with country codes can exceed 15 chars
alter table members alter column phone type varchar(25);

-- add a rating column to instructors to track performance scores over time
alter table instructors add column rating numeric(3,1) default 5.0;

-- a session's max_participants was not modelled initially; add it with a sensible default
alter table schedule add column max_participants int not null default 20;

-- rename note to payment_note in payments for better clarity across the codebase
alter table payments rename column note to payment_note;

-- drop the emergency_contact default so future nulls surface missing data explicitly
alter table members alter column emergency_contact drop default;


-- =============================================================
--  PART 4: INSERT — TRUNCATE (correct FK order)
-- =============================================================

truncate table
    fitness_club_db.payments,
    fitness_club_db.schedule_enrollment,
    fitness_club_db.schedule,
    fitness_club_db.facilities,
    fitness_club_db.classes,
    fitness_club_db.instructors,
    fitness_club_db.members,
    fitness_club_db.membership_types
restart identity cascade;


-- =============================================================
--  PART 4: INSERT — MEMBERSHIP TYPES (5 rows, multi-row)
-- =============================================================

insert into membership_types (name, duration_months, price, access_level, is_active)
values
    ('Gold',     12,  599.99, 'VIP',      true),
    ('Silver',    6,  299.99, 'Standard', true),
    ('Bronze',    3,  149.99, 'Basic',    true),
    ('Platinum', 24, 1099.99, 'VIP',      true),
    ('Trial',     1,   49.99, 'Basic',    true);


-- =============================================================
--  PART 4: INSERT — MEMBERS (10 rows, subquery FKs)
-- =============================================================

insert into members (first_name, last_name, email, phone, date_of_birth, membership_type_id, joined_date)
values
    ('John',    'Smith',    'john.smith@email.kz',    '+77011234567', '2001-02-15',
        (select membership_type_id from membership_types where name = 'Gold'),
        '2026-02-01'),
    ('Dias',    'Ermekov',  'dias.ermekov@email.kz',  '+77027654321', '2003-04-23',
        (select membership_type_id from membership_types where name = 'Silver'),
        '2026-02-15'),
    ('Anna',    'Brown',    'anna.brown@email.kz',    '+77031112233', '2006-03-10',
        (select membership_type_id from membership_types where name = 'Silver'),
        '2026-03-01'),
    ('Maria',   'Ivanova',  'maria.ivanova@email.kz', '+77042223344', '1995-07-22',
        (select membership_type_id from membership_types where name = 'Platinum'),
        '2026-01-10'),
    ('Alexei',  'Petrov',   'alexei.petrov@email.kz', '+77053334455', '1988-11-05',
        (select membership_type_id from membership_types where name = 'Bronze'),
        '2026-03-15'),
    ('Sara',    'Nurova',   'sara.nurova@email.kz',   '+77064445566', '2000-09-18',
        (select membership_type_id from membership_types where name = 'Gold'),
        '2026-02-20'),
    ('Timur',   'Bekov',    'timur.bekove@email.kz',  '+77075556677', '1997-12-30',
        (select membership_type_id from membership_types where name = 'Trial'),
        '2026-04-01'),
    ('Elena',   'Volkova',  'elena.volkova@email.kz', '+77086667788', '2002-05-14',
        (select membership_type_id from membership_types where name = 'Silver'),
        '2026-03-10'),
    ('Bauyrzhan','Seitkali','bau.seitkali@email.kz',  '+77097778899', '1993-01-27',
        (select membership_type_id from membership_types where name = 'Bronze'),
        '2026-04-05'),
    ('Dinara',  'Akhmet',   'dinara.akhmet@email.kz', '+77008889900', '1999-08-03',
        (select membership_type_id from membership_types where name = 'Gold'),
        '2026-01-20');


-- =============================================================
--  PART 4: INSERT — INSTRUCTORS (5 rows)
-- =============================================================

insert into instructors (first_name, last_name, specialization, hourly_rate)
values
    ('Mike',    'Johnson',  'Yoga',    25.00),
    ('John',    'Pork',     'MMA',     30.00),
    ('Sara',    'Lee',      'Cardio',  28.00),
    ('Arman',   'Dzhaksybekov', 'Gym', 22.00),
    ('Natalia', 'Serova',   'Pilates', 26.00);


-- =============================================================
--  PART 4: INSERT — CLASSES (5 rows)
-- =============================================================

insert into classes (name, description, category)
values
    ('Morning Yoga',    'Gentle flow to start your day with breath and movement.', 'Yoga'),
    ('HIIT Training',   'High-intensity interval training for maximum calorie burn.', 'Cardio'),
    ('MMA Basics',      'Introduction to mixed martial arts: striking and grappling.', 'Combat'),
    ('Strength Circuit','Full-body resistance training with free weights and machines.', 'Strength'),
    ('Evening Pilates', 'Core-focused pilates session ideal for stress relief.', 'Wellness');


-- =============================================================
--  PART 4: INSERT — FACILITIES (5 rows)
-- =============================================================

insert into facilities (name, capacity, location_description)
values
    ('Room A',       30, 'First floor, east wing'),
    ('Gym Hall',     50, 'Second floor, main area'),
    ('Yoga Studio',  20, 'Third floor, quiet zone'),
    ('Combat Room',  25, 'Basement level'),
    ('Pilates Loft', 15, 'Third floor, west wing');


-- =============================================================
--  PART 4: INSERT — SCHEDULE (10 rows, subquery FKs)
-- =============================================================

insert into schedule (class_id, instructor_id, facility_id, session_date, duration_minutes, max_participants)
values
    (
        (select class_id      from classes     where name            = 'Morning Yoga'),
        (select instructor_id from instructors where last_name       = 'Johnson'),
        (select facility_id   from facilities  where name            = 'Yoga Studio'),
        '2026-05-01', 60, 20
    ),
    (
        (select class_id      from classes     where name            = 'HIIT Training'),
        (select instructor_id from instructors where last_name       = 'Lee'),
        (select facility_id   from facilities  where name            = 'Room A'),
        '2026-05-02', 45, 25
    ),
    (
        (select class_id      from classes     where name            = 'MMA Basics'),
        (select instructor_id from instructors where last_name       = 'Pork'),
        (select facility_id   from facilities  where name            = 'Combat Room'),
        '2026-05-03', 90, 15
    ),
    (
        (select class_id      from classes     where name            = 'Strength Circuit'),
        (select instructor_id from instructors where last_name       = 'Dzhaksybekov'),
        (select facility_id   from facilities  where name            = 'Gym Hall'),
        '2026-05-04', 60, 30
    ),
    (
        (select class_id      from classes     where name            = 'Evening Pilates'),
        (select instructor_id from instructors where last_name       = 'Serova'),
        (select facility_id   from facilities  where name            = 'Pilates Loft'),
        '2026-05-05', 50, 15
    ),
    (
        (select class_id      from classes     where name            = 'Morning Yoga'),
        (select instructor_id from instructors where last_name       = 'Johnson'),
        (select facility_id   from facilities  where name            = 'Yoga Studio'),
        '2026-05-08', 60, 20
    ),
    (
        (select class_id      from classes     where name            = 'HIIT Training'),
        (select instructor_id from instructors where last_name       = 'Lee'),
        (select facility_id   from facilities  where name            = 'Room A'),
        '2026-05-09', 45, 25
    ),
    (
        (select class_id      from classes     where name            = 'MMA Basics'),
        (select instructor_id from instructors where last_name       = 'Pork'),
        (select facility_id   from facilities  where name            = 'Combat Room'),
        '2026-05-10', 90, 15
    ),
    (
        (select class_id      from classes     where name            = 'Strength Circuit'),
        (select instructor_id from instructors where last_name       = 'Dzhaksybekov'),
        (select facility_id   from facilities  where name            = 'Gym Hall'),
        '2026-05-11', 60, 30
    ),
    (
        (select class_id      from classes     where name            = 'Evening Pilates'),
        (select instructor_id from instructors where last_name       = 'Serova'),
        (select facility_id   from facilities  where name            = 'Pilates Loft'),
        '2026-05-12', 50, 15
    );


-- =============================================================
--  PART 4: INSERT — SCHEDULE_ENROLLMENT
--  Using INSERT … SELECT to populate the junction table (required)
--  Enroll all VIP/Gold members into every Yoga session
-- =============================================================

insert into schedule_enrollment (member_id, schedule_id)
select
    m.member_id,
    s.schedule_id
from members m
join membership_types mt on mt.membership_type_id = m.membership_type_id
join schedule s          on s.class_id = (select class_id from classes where name = 'Morning Yoga')
where mt.access_level = 'VIP';

-- individual enrollments (subquery FKs)
insert into schedule_enrollment (member_id, schedule_id)
values
    (
        (select member_id   from members  where email = 'dias.ermekov@email.kz'),
        (select schedule_id from schedule where class_id = (select class_id from classes where name = 'HIIT Training')
                                           and session_date = '2026-05-02')
    ),
    (
        (select member_id   from members  where email = 'anna.brown@email.kz'),
        (select schedule_id from schedule where class_id = (select class_id from classes where name = 'MMA Basics')
                                           and session_date = '2026-05-03')
    ),
    (
        (select member_id   from members  where email = 'alexei.petrov@email.kz'),
        (select schedule_id from schedule where class_id = (select class_id from classes where name = 'Strength Circuit')
                                           and session_date = '2026-05-04')
    ),
    (
        (select member_id   from members  where email = 'timur.bekove@email.kz'),
        (select schedule_id from schedule where class_id = (select class_id from classes where name = 'Evening Pilates')
                                           and session_date = '2026-05-05')
    ),
    (
        (select member_id   from members  where email = 'elena.volkova@email.kz'),
        (select schedule_id from schedule where class_id = (select class_id from classes where name = 'HIIT Training')
                                           and session_date = '2026-05-09')
    );


-- =============================================================
--  PART 4: INSERT — PAYMENTS (10 rows, subquery FKs)
-- =============================================================

insert into payments (amount, payment_method, member_id, payment_date, payment_note)
values
    (599.99, 'Card',
        (select member_id from members where email = 'john.smith@email.kz'),
        '2026-02-01 10:00:00', 'Gold membership — annual'),
    (299.99, 'Cash',
        (select member_id from members where email = 'dias.ermekov@email.kz'),
        '2026-02-15 11:30:00', 'Silver membership — 6 months'),
    (299.99, 'Transfer',
        (select member_id from members where email = 'anna.brown@email.kz'),
        '2026-03-01 09:00:00', 'Silver membership — 6 months'),
    (1099.99, 'Card',
        (select member_id from members where email = 'maria.ivanova@email.kz'),
        '2026-01-10 14:00:00', 'Platinum membership — 2 years'),
    (149.99, 'Cash',
        (select member_id from members where email = 'alexei.petrov@email.kz'),
        '2026-03-15 16:00:00', 'Bronze membership — 3 months'),
    (599.99, 'Card',
        (select member_id from members where email = 'sara.nurova@email.kz'),
        '2026-02-20 12:00:00', 'Gold membership — annual'),
    (49.99, 'Card',
        (select member_id from members where email = 'timur.bekove@email.kz'),
        '2026-04-01 10:45:00', 'Trial membership — 1 month'),
    (299.99, 'Transfer',
        (select member_id from members where email = 'elena.volkova@email.kz'),
        '2026-03-10 08:30:00', 'Silver membership — 6 months'),
    (149.99, 'Cash',
        (select member_id from members where email = 'bau.seitkali@email.kz'),
        '2026-04-05 17:15:00', 'Bronze membership — 3 months'),
    (599.99, 'Card',
        (select member_id from members where email = 'dinara.akhmet@email.kz'),
        '2026-01-20 11:00:00', 'Gold membership — annual');


-- =============================================================
--  PART 5: UPDATE
-- =============================================================

-- apply a 10 % loyalty discount to all Gold membership payments made via Card
update payments
set    amount = amount * 0.90
where  payment_method = 'Card'
  and  member_id in (
        select m.member_id
        from   members m
        join   membership_types mt on mt.membership_type_id = m.membership_type_id
        where  mt.name = 'Gold'
  );

-- raise the hourly rate of every instructor whose class category is 'Combat' or 'Strength'
-- to reflect specialised demand; new rate = current rate + 5.00
update instructors i
set    hourly_rate = hourly_rate + 5.00
from   schedule   s
join   classes    c on c.class_id = s.class_id
where  s.instructor_id = i.instructor_id
  and  c.category in ('Combat', 'Strength');


-- =============================================================
--  PART 5: DELETE (wrapped in transaction — data is preserved)
-- =============================================================

-- remove trial memberships whose single-month period has lapsed (joined before May 2026)
-- payments must be deleted first to satisfy the FK constraint on payments.member_id
-- wrapped in BEGIN … ROLLBACK so data survives the defense session
begin;

delete from payments
where  member_id in (
    select member_id from members
    where  membership_type_id = (select membership_type_id from membership_types where name = 'Trial')
      and  joined_date < '2026-05-01'
);

delete from members
where  membership_type_id = (select membership_type_id from membership_types where name = 'Trial')
  and  joined_date < '2026-05-01'
returning member_id, first_name, last_name, joined_date;

rollback;


-- =============================================================
--  PART 6: GRANT / REVOKE
-- =============================================================

drop role if exists fitness_club_readonly;
drop role if exists fitness_club_writer;

-- read-only role: used by reporting tools and dashboards that only need SELECT access
create role fitness_club_readonly;

-- writer role: used by front-desk staff who record new payments and member sign-ups
create role fitness_club_writer;

grant select on all tables in schema fitness_club_db to fitness_club_readonly;

grant insert, update on fitness_club_db.payments to fitness_club_writer;

-- revoke UPDATE on payments from writer role: payments must never be altered after creation
-- to maintain an immutable financial audit log; corrections require a new offsetting record
revoke update on fitness_club_db.payments from fitness_club_writer;
