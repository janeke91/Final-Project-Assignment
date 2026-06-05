-- =============================================================
--  PART 1: DATABASE + SCHEMA SETUP
-- =============================================================

create schema if not exists fitness_club_db;
set search_path to fitness_club_db;


-- =============================================================
--  PART 2: CREATE — TABLE DEFINITIONS + CONSTRAINTS
-- =============================================================

create table if not exists membership_types (
    membership_type_id  serial          primary key,
    name                varchar(50)     not null unique,                          -- UNIQUE natural key
    duration_months     int             not null check (duration_months > 0),     -- CHECK: positive duration
    price               numeric(10,2)   not null check (price >= 0),              -- CHECK: non-negative money
    access_level        varchar(50)     not null check (access_level in ('VIP', 'Standard', 'Basic')),  -- CHECK: enum filter
    is_active           boolean         not null default true,                    -- DEFAULT: new plans are active by default
    record_ts           date            not null default current_date
);

create table if not exists members (
    member_id           serial          primary key,
    first_name          varchar(50)     not null,
    last_name           varchar(50)     not null,
    email               varchar(100)    not null unique,                          -- UNIQUE natural key
    phone               varchar(20)     not null,                                 -- NOT NULL constraint for critical data
    date_of_birth       date            not null,
    membership_type_id  int             not null references membership_types(membership_type_id)
                                            on delete restrict,                   -- RESTRICT: protect parent records from accidental loss
    joined_date         date            not null check (joined_date > date '2026-01-01'), -- CHECK: contract date verification
    record_ts           date            not null default current_date
);

create table if not exists instructors (
    instructor_id       serial          primary key,
    first_name          varchar(50)     not null,
    last_name           varchar(50)     not null,
    specialization      varchar(50)     not null check (specialization in ('Yoga', 'Cardio', 'MMA', 'Gym', 'Pilates')), -- CHECK: enum filter
    hourly_rate         numeric(10,2)   not null check (hourly_rate >= 0),        -- CHECK: non-negative salary rates
    record_ts           date            not null default current_date
);

create table if not exists classes (
    class_id            serial          primary key,
    name                varchar(100)    not null unique,                          -- UNIQUE natural key
    description         text,
    category            varchar(50)     not null check (category in ('Yoga', 'Cardio', 'Strength', 'Combat', 'Wellness')), -- CHECK: enum filter
    record_ts           date            not null default current_date
);

create table if not exists facilities (
    facility_id         serial          primary key,
    name                varchar(50)     not null,
    capacity            int             not null check (capacity >= 0),           -- CHECK: physical capacity limits
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
    duration_hours      numeric(5,2)    generated always as (duration_minutes / 60.0) stored, -- GENERATED: computed virtual column
    record_ts           date            not null default current_date
);

create table if not exists schedule_enrollment (
    member_id           int             not null references members(member_id)
                                            on delete cascade,                    -- CASCADE: auto-purge enrollment links on member departure
    schedule_id         int             not null references schedule(schedule_id)
                                            on delete cascade,                    -- CASCADE: auto-purge records if a session is cancelled
    primary key (member_id, schedule_id),                                         -- Composite primary key prevents duplicates
    enrolled_at         timestamp       not null default current_timestamp,
    record_ts           date            not null default current_date
);

create table if not exists payments (
    payment_id          serial          primary key,
    amount              numeric(10,2)   not null check (amount >= 0),
    payment_date        timestamp       not null default current_timestamp,
    payment_method      varchar(30)     not null check (payment_method in ('Cash', 'Card', 'Transfer')), -- CHECK: enum filter
    member_id           int             not null references members(member_id)
                                            on delete restrict,
    note                text,
    record_ts           date            not null default current_date,
    check (payment_date > '2026-01-01 00:00:00')                                 -- CHECK: billing date boundary check
);


-- =============================================================
--  PART 3: ALTER TABLE (Idempotent structural evolution)
-- =============================================================

-- 1. Add emergency contact column only if missing (prevents script failure on consecutive re-runs)
alter table members add column if not exists emergency_contact varchar(20) default 'N/A';

-- 2. Widen the phone data field to accurately fit international country codes
alter table members alter column phone type varchar(25);

-- 3. Add quality evaluation rating column to instructors only if it does not exist yet
alter table instructors add column if not exists rating numeric(3,1) default 5.0;

-- 4. Add safety participant capacity limit constraint to schedule slots if missing
alter table schedule add column if not exists max_participants int not null default 20;

-- 5. Safe column rename logic: uses a dynamic anonymous block (DO) to look up information_schema.
-- This ensures the script won't crash when 'note' has already been changed to 'payment_note'.
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'fitness_club_db'
          and table_name   = 'payments'
          and column_name  = 'note'
    ) then
        alter table payments rename column note to payment_note;
    end if;
end;
$$;

-- 6. Strip default constraint so application code is forced to handle explicit parameters
alter table members alter column emergency_contact drop default;


-- =============================================================
--  PART 4: INSERT — TRUNCATE (Strict foreign key execution dependency)
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
restart identity cascade;                         -- RESTART IDENTITY resets sequences; CASCADE bypasses parent table locks


-- =============================================================
--  PART 4: INSERT — MEMBERSHIP TYPES (5 rows, multi-row layout)
-- =============================================================

insert into membership_types (name, duration_months, price, access_level, is_active)
values
    ('Gold',     12,  599.99, 'VIP',      true),
    ('Silver',    6,  299.99, 'Standard', true),
    ('Bronze',    3,  149.99, 'Basic',    true),
    ('Platinum', 24, 1099.99, 'VIP',      true),
    ('Trial',     1,   49.99, 'Basic',    true);


-- =============================================================
--  PART 4: INSERT — MEMBERS (10 rows, relational subquery lookups)
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
    ('Mike',    'Johnson',      'Yoga',    25.00),
    ('John',    'Pork',         'MMA',     30.00),
    ('Sara',    'Lee',          'Cardio',  28.00),
    ('Arman',   'Dzhaksybekov', 'Gym',     22.00),
    ('Natalia', 'Serova',       'Pilates', 26.00);


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
--  PART 4: INSERT — SCHEDULE (10 rows, nested foreign key assignments)
-- =============================================================

insert into schedule (class_id, instructor_id, facility_id, session_date, duration_minutes, max_participants)
values
    (
        (select class_id      from classes     where name      = 'Morning Yoga'),
        (select instructor_id from instructors where last_name = 'Johnson'),
        (select facility_id   from facilities  where name      = 'Yoga Studio'),
        '2026-05-01', 60, 20
    ),
    (
        (select class_id      from classes     where name      = 'HIIT Training'),
        (select instructor_id from instructors where last_name = 'Lee'),
        (select facility_id   from facilities  where name      = 'Room A'),
        '2026-05-02', 45, 25
    ),
    (
        (select class_id      from classes     where name      = 'MMA Basics'),
        (select instructor_id from instructors where last_name = 'Pork'),
        (select facility_id   from facilities  where name      = 'Combat Room'),
        '2026-05-03', 90, 15
    ),
    (
        (select class_id      from classes     where name      = 'Strength Circuit'),
        (select instructor_id from instructors where last_name = 'Dzhaksybekov'),
        (select facility_id   from facilities  where name      = 'Gym Hall'),
        '2026-05-04', 60, 30
    ),
    (
        (select class_id      from classes     where name      = 'Evening Pilates'),
        (select instructor_id from instructors where last_name = 'Serova'),
        (select facility_id   from facilities  where name      = 'Pilates Loft'),
        '2026-05-05', 50, 15
    ),
    (
        (select class_id      from classes     where name      = 'Morning Yoga'),
        (select instructor_id from instructors where last_name = 'Johnson'),
        (select facility_id   from facilities  where name      = 'Yoga Studio'),
        '2026-05-08', 60, 20
    ),
    (
        (select class_id      from classes     where name      = 'HIIT Training'),
        (select instructor_id from instructors where last_name = 'Lee'),
        (select facility_id   from facilities  where name      = 'Room A'),
        '2026-05-09', 45, 25
    ),
    (
        (select class_id      from classes     where name      = 'MMA Basics'),
        (select instructor_id from instructors where last_name = 'Pork'),
        (select facility_id   from facilities  where name      = 'Combat Room'),
        '2026-05-10', 90, 15
    ),
    (
        (select class_id      from classes     where name      = 'Strength Circuit'),
        (select instructor_id from instructors where last_name = 'Dzhaksybekov'),
        (select facility_id   from facilities  where name      = 'Gym Hall'),
        '2026-05-11', 60, 30
    ),
    (
        (select class_id      from classes     where name      = 'Evening Pilates'),
        (select instructor_id from instructors where last_name = 'Serova'),
        (select facility_id   from facilities  where name      = 'Pilates Loft'),
        '2026-05-12', 50, 15
    );


-- =============================================================
--  PART 4: INSERT — SCHEDULE_ENROLLMENT (Junction table populations)
-- =============================================================

-- Populate junction table utilizing an INSERT ... SELECT statement
insert into schedule_enrollment (member_id, schedule_id)
select
    m.member_id,
    s.schedule_id
from members m
join membership_types mt on mt.membership_type_id = m.membership_type_id
join schedule s          on s.class_id = (select class_id from classes where name = 'Morning Yoga')
where mt.access_level = 'VIP';                     -- Automatically map all VIP profiles to morning yoga courses

-- Dedicated individual registrations using granular lookup filters
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
--  PART 4: INSERT — PAYMENTS (10 rows, relational mappings)
-- =============================================================

insert into payments (amount, payment_method, member_id, payment_date, payment_note)
values
    (599.99,  'Card',
        (select member_id from members where email = 'john.smith@email.kz'),
        '2026-02-01 10:00:00', 'Gold membership — annual'),
    (299.99,  'Cash',
        (select member_id from members where email = 'dias.ermekov@email.kz'),
        '2026-02-15 11:30:00', 'Silver membership — 6 months'),
    (299.99,  'Transfer',
        (select member_id from members where email = 'anna.brown@email.kz'),
        '2026-03-01 09:00:00', 'Silver membership — 6 months'),
    (1099.99, 'Card',
        (select member_id from members where email = 'maria.ivanova@email.kz'),
        '2026-01-10 14:00:00', 'Platinum membership — 2 years'),
    (149.99,  'Cash',
        (select member_id from members where email = 'alexei.petrov@email.kz'),
        '2026-03-15 16:00:00', 'Bronze membership — 3 months'),
    (599.99,  'Card',
        (select member_id from members where email = 'sara.nurova@email.kz'),
        '2026-02-20 12:00:00', 'Gold membership — annual'),
    (49.99,   'Card',
        (select member_id from members where email = 'timur.bekove@email.kz'),
        '2026-04-01 10:45:00', 'Trial membership — 1 month'),
    (299.99,  'Transfer',
        (select member_id from members where email = 'elena.volkova@email.kz'),
        '2026-03-10 08:30:00', 'Silver membership — 6 months'),
    (149.99,  'Cash',
        (select member_id from members where email = 'bau.seitkali@email.kz'),
        '2026-04-05 17:15:00', 'Bronze membership — 3 months'),
    (599.99,  'Card',
        (select member_id from members where email = 'dinara.akhmet@email.kz'),
        '2026-01-20 11:00:00', 'Gold membership — annual');


-- =============================================================
--  PART 5: UPDATE (Relational business rule execution)
-- =============================================================

-- Apply a 10% loyalty discount to all Card payments linked to Gold packages
update payments
set    amount = amount * 0.90
where  payment_method = 'Card'
  and  member_id in (
        select m.member_id
        from   members m
        join   membership_types mt on mt.membership_type_id = m.membership_type_id
        where  mt.name = 'Gold'
  );

-- Raise rate by 5.00 for instructors handling specialized categories (Combat/Strength)
update instructors i
set    hourly_rate = hourly_rate + 5.00
from   schedule   s
join   classes    c on c.class_id = s.class_id
where  s.instructor_id = i.instructor_id
  and  c.category in ('Combat', 'Strength');


-- =============================================================
--  PART 5: DELETE (Wrapped in explicit testing transaction)
-- =============================================================

-- Explicit transaction blocks real execution to maintain data integrity during defense
begin;

-- Financial transaction records must be wiped first to prevent ON DELETE RESTRICT violations
delete from payments
where  member_id in (
    select member_id from members
    where  membership_type_id = (select membership_type_id from membership_types where name = 'Trial')
      and  joined_date < '2026-05-01'
);

-- Delete expired trial account references
delete from members
where  membership_type_id = (select membership_type_id from membership_types where name = 'Trial')
  and  joined_date < '2026-05-01'
returning member_id, first_name, last_name, joined_date; -- RETURNING fetches structured output logs of dropped objects

rollback;                                         -- ROLLBACK securely restores data to original state


-- =============================================================
--  PART 6: GRANT / REVOKE (Role-based access security controls)
-- =============================================================

-- Clear obsolete roles prior to configuration re-entry
revoke all privileges on all tables in schema fitness_club_db from fitness_club_readonly;
revoke all privileges on all tables in schema fitness_club_db from fitness_club_writer;

drop role if exists fitness_club_readonly;
drop role if exists fitness_club_writer;

-- Instantiate explicit service access groups
create role fitness_club_readonly;
create role fitness_club_writer;

-- Assign analytical privileges to the reporting group
grant select on all tables in schema fitness_club_db to fitness_club_readonly;

-- Provide registration privileges to data entry desk personnel
grant insert, update on fitness_club_db.payments to fitness_club_writer;

-- Enforce strict immutability rule: audit logs cannot be updated after creation
revoke update on fitness_club_db.payments from fitness_club_writer;
