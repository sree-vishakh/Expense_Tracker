-- ============================================================
-- EXPENSE TRACKER - Oracle Database Schema
-- Author  : sree-vishakh
-- File    : database/schema.sql
-- ============================================================


-- ============================================================
-- STEP 1: CREATE SEQUENCES (auto-increment IDs)
-- ============================================================

CREATE SEQUENCE seq_users
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE SEQUENCE seq_categories
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE SEQUENCE seq_expenses
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;


-- ============================================================
-- STEP 2: CREATE TABLES
-- ============================================================

-- USERS table
-- Stores login credentials for each person
CREATE TABLE users (
    user_id       NUMBER         PRIMARY KEY,
    username      VARCHAR2(50)   NOT NULL UNIQUE,
    email         VARCHAR2(100)  NOT NULL UNIQUE,
    password_hash VARCHAR2(255)  NOT NULL,       -- never store plain password
    created_at    DATE           DEFAULT SYSDATE NOT NULL,
    is_active     CHAR(1)        DEFAULT 'Y'     NOT NULL,
    CONSTRAINT chk_users_active CHECK (is_active IN ('Y', 'N'))
);

-- CATEGORIES table
-- Stores expense/income categories like Food, Salary etc.
CREATE TABLE categories (
    category_id   NUMBER         PRIMARY KEY,
    user_id       NUMBER         NOT NULL,
    category_name VARCHAR2(50)   NOT NULL,
    category_type VARCHAR2(10)   NOT NULL,       -- 'INCOME' or 'EXPENSE'
    color_code    VARCHAR2(10)   DEFAULT '#888888',
    created_at    DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_cat_user     FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_cat_type    CHECK (category_type IN ('INCOME', 'EXPENSE')),
    CONSTRAINT uq_cat_name     UNIQUE (user_id, category_name)
);

-- EXPENSES table
-- Every transaction — income or expense
CREATE TABLE expenses (
    expense_id    NUMBER          PRIMARY KEY,
    user_id       NUMBER          NOT NULL,
    category_id   NUMBER          NOT NULL,
    description   VARCHAR2(255)   NOT NULL,
    amount        NUMBER(12, 2)   NOT NULL,
    txn_type      VARCHAR2(10)    NOT NULL,      -- 'INCOME' or 'EXPENSE'
    txn_date      DATE            DEFAULT SYSDATE NOT NULL,
    created_at    DATE            DEFAULT SYSDATE NOT NULL,
    is_deleted    CHAR(1)         DEFAULT 'N'    NOT NULL,
    CONSTRAINT fk_exp_user     FOREIGN KEY (user_id)     REFERENCES users(user_id)      ON DELETE CASCADE,
    CONSTRAINT fk_exp_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT chk_exp_type    CHECK (txn_type IN ('INCOME', 'EXPENSE')),
    CONSTRAINT chk_exp_amount  CHECK (amount > 0),
    CONSTRAINT chk_exp_deleted CHECK (is_deleted IN ('Y', 'N'))
);


-- ============================================================
-- STEP 3: CREATE INDEXES (faster queries)
-- ============================================================

CREATE INDEX idx_expenses_user    ON expenses(user_id);
CREATE INDEX idx_expenses_date    ON expenses(txn_date);
CREATE INDEX idx_expenses_type    ON expenses(txn_type);
CREATE INDEX idx_categories_user  ON categories(user_id);


-- ============================================================
-- STEP 4: PL/SQL PROCEDURES
-- ============================================================

-- -------------------------------------------------------
-- 4a. ADD_USER — register a new user
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_user (
    p_username      IN  users.username%TYPE,
    p_email         IN  users.email%TYPE,
    p_password_hash IN  users.password_hash%TYPE,
    p_user_id       OUT users.user_id%TYPE
)
AS
BEGIN
    p_user_id := seq_users.NEXTVAL;

    INSERT INTO users (user_id, username, email, password_hash)
    VALUES (p_user_id, p_username, p_email, p_password_hash);

    COMMIT;

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20001, 'Username or email already exists.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_user;
/


-- -------------------------------------------------------
-- 4b. ADD_CATEGORY — add a category for a user
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_category (
    p_user_id       IN  categories.user_id%TYPE,
    p_name          IN  categories.category_name%TYPE,
    p_type          IN  categories.category_type%TYPE,
    p_color         IN  categories.color_code%TYPE,
    p_category_id   OUT categories.category_id%TYPE
)
AS
BEGIN
    p_category_id := seq_categories.NEXTVAL;

    INSERT INTO categories (category_id, user_id, category_name, category_type, color_code)
    VALUES (p_category_id, p_user_id, p_name, UPPER(p_type), p_color);

    COMMIT;

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20002, 'Category already exists for this user.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_category;
/


-- -------------------------------------------------------
-- 4c. ADD_EXPENSE — add a new transaction
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_expense (
    p_user_id       IN  expenses.user_id%TYPE,
    p_category_id   IN  expenses.category_id%TYPE,
    p_description   IN  expenses.description%TYPE,
    p_amount        IN  expenses.amount%TYPE,
    p_type          IN  expenses.txn_type%TYPE,
    p_date          IN  expenses.txn_date%TYPE,
    p_expense_id    OUT expenses.expense_id%TYPE
)
AS
BEGIN
    p_expense_id := seq_expenses.NEXTVAL;

    INSERT INTO expenses (
        expense_id, user_id, category_id,
        description, amount, txn_type, txn_date
    )
    VALUES (
        p_expense_id, p_user_id, p_category_id,
        p_description, p_amount, UPPER(p_type), p_date
    );

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_expense;
/


-- -------------------------------------------------------
-- 4d. DELETE_EXPENSE — soft delete (never hard delete)
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE delete_expense (
    p_expense_id  IN expenses.expense_id%TYPE,
    p_user_id     IN expenses.user_id%TYPE
)
AS
    v_count NUMBER;
BEGIN
    -- Make sure this expense belongs to this user
    SELECT COUNT(*) INTO v_count
    FROM expenses
    WHERE expense_id = p_expense_id
      AND user_id    = p_user_id
      AND is_deleted = 'N';

    IF v_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Expense not found or already deleted.');
    END IF;

    UPDATE expenses
    SET    is_deleted = 'Y'
    WHERE  expense_id = p_expense_id
      AND  user_id    = p_user_id;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END delete_expense;
/


-- -------------------------------------------------------
-- 4e. GET_MONTHLY_SUMMARY — total income & expense by month
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE get_monthly_summary (
    p_user_id   IN  expenses.user_id%TYPE,
    p_year      IN  NUMBER,
    p_month     IN  NUMBER,
    p_income    OUT NUMBER,
    p_expense   OUT NUMBER,
    p_balance   OUT NUMBER
)
AS
BEGIN
    SELECT
        NVL(SUM(CASE WHEN txn_type = 'INCOME'  THEN amount ELSE 0 END), 0),
        NVL(SUM(CASE WHEN txn_type = 'EXPENSE' THEN amount ELSE 0 END), 0)
    INTO p_income, p_expense
    FROM expenses
    WHERE user_id    = p_user_id
      AND is_deleted = 'N'
      AND EXTRACT(YEAR  FROM txn_date) = p_year
      AND EXTRACT(MONTH FROM txn_date) = p_month;

    p_balance := p_income - p_expense;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END get_monthly_summary;
/


-- ============================================================
-- STEP 5: USEFUL VIEWS
-- ============================================================

-- Full expense list with category name (easy for API queries)
CREATE OR REPLACE VIEW vw_expenses AS
SELECT
    e.expense_id,
    e.user_id,
    u.username,
    c.category_name,
    c.color_code,
    e.description,
    e.amount,
    e.txn_type,
    e.txn_date,
    EXTRACT(YEAR  FROM e.txn_date) AS txn_year,
    EXTRACT(MONTH FROM e.txn_date) AS txn_month,
    e.created_at
FROM  expenses   e
JOIN  users      u ON e.user_id    = u.user_id
JOIN  categories c ON e.category_id = c.category_id
WHERE e.is_deleted = 'N';

-- Monthly summary view
CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT
    user_id,
    EXTRACT(YEAR  FROM txn_date) AS txn_year,
    EXTRACT(MONTH FROM txn_date) AS txn_month,
    SUM(CASE WHEN txn_type = 'INCOME'  THEN amount ELSE 0 END) AS total_income,
    SUM(CASE WHEN txn_type = 'EXPENSE' THEN amount ELSE 0 END) AS total_expense,
    SUM(CASE WHEN txn_type = 'INCOME'  THEN amount ELSE -amount END) AS net_balance,
    COUNT(*) AS txn_count
FROM  expenses
WHERE is_deleted = 'N'
GROUP BY user_id,
         EXTRACT(YEAR  FROM txn_date),
         EXTRACT(MONTH FROM txn_date);


-- ============================================================
-- STEP 6: SEED DEFAULT CATEGORIES
-- ============================================================
-- Run this after creating your first user (user_id = 1)

/*
DECLARE
    v_cat_id NUMBER;
BEGIN
    add_category(1, 'Food',          'EXPENSE', '#e67e22', v_cat_id);
    add_category(1, 'Transport',     'EXPENSE', '#2980b9', v_cat_id);
    add_category(1, 'Shopping',      'EXPENSE', '#8e5fd4', v_cat_id);
    add_category(1, 'Health',        'EXPENSE', '#27ae60', v_cat_id);
    add_category(1, 'Entertainment', 'EXPENSE', '#e91e63', v_cat_id);
    add_category(1, 'Utilities',     'EXPENSE', '#16a085', v_cat_id);
    add_category(1, 'Salary',        'INCOME',  '#2ecc71', v_cat_id);
    add_category(1, 'Freelance',     'INCOME',  '#f1c40f', v_cat_id);
    add_category(1, 'Investment',    'INCOME',  '#1abc9c', v_cat_id);
    add_category(1, 'Other',         'EXPENSE', '#7f8c8d', v_cat_id);
    DBMS_OUTPUT.PUT_LINE('Default categories created.');
END;
/
*/

-- ============================================================
-- END OF SCHEMA
-- ============================================================
