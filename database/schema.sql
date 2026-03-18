-- ============================================================
-- EXPENSE TRACKER - Oracle Database Schema
-- Author  : sree-vishakh
-- Tables  : ET_USERS, ET_CATEGORIES, ET_EXPENSES
-- ============================================================


-- ============================================================
-- STEP 1: CREATE SEQUENCES
-- ============================================================

CREATE SEQUENCE seq_et_users
    START WITH 1
    INCREMENT BY 1
    NOCACHE NOCYCLE;

CREATE SEQUENCE seq_et_categories
    START WITH 1
    INCREMENT BY 1
    NOCACHE NOCYCLE;

CREATE SEQUENCE seq_et_expenses
    START WITH 1
    INCREMENT BY 1
    NOCACHE NOCYCLE;


-- ============================================================
-- STEP 2: CREATE TABLES
-- ============================================================

-- ET_USERS — stores app login credentials
CREATE TABLE et_users (
    user_id       NUMBER         PRIMARY KEY,
    username      VARCHAR2(50)   NOT NULL UNIQUE,
    email         VARCHAR2(100)  NOT NULL UNIQUE,
    password_hash VARCHAR2(255)  NOT NULL,
    created_at    DATE           DEFAULT SYSDATE NOT NULL,
    is_active     CHAR(1)        DEFAULT 'Y'     NOT NULL,
    CONSTRAINT chk_et_users_active CHECK (is_active IN ('Y', 'N'))
);

-- ET_CATEGORIES — expense/income categories per user
CREATE TABLE et_categories (
    category_id   NUMBER         PRIMARY KEY,
    user_id       NUMBER         NOT NULL,
    category_name VARCHAR2(50)   NOT NULL,
    category_type VARCHAR2(10)   NOT NULL,
    color_code    VARCHAR2(10)   DEFAULT '#888888',
    created_at    DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_etcat_user  FOREIGN KEY (user_id) REFERENCES et_users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_etcat_type CHECK (category_type IN ('INCOME', 'EXPENSE')),
    CONSTRAINT uq_etcat_name  UNIQUE (user_id, category_name)
);

-- ET_EXPENSES — every transaction
CREATE TABLE et_expenses (
    expense_id    NUMBER          PRIMARY KEY,
    user_id       NUMBER          NOT NULL,
    category_id   NUMBER          NOT NULL,
    description   VARCHAR2(255)   NOT NULL,
    amount        NUMBER(12, 2)   NOT NULL,
    txn_type      VARCHAR2(10)    NOT NULL,
    txn_date      DATE            DEFAULT SYSDATE NOT NULL,
    created_at    DATE            DEFAULT SYSDATE NOT NULL,
    is_deleted    CHAR(1)         DEFAULT 'N'     NOT NULL,
    CONSTRAINT fk_etexp_user  FOREIGN KEY (user_id)     REFERENCES et_users(user_id)      ON DELETE CASCADE,
    CONSTRAINT fk_etexp_cat   FOREIGN KEY (category_id) REFERENCES et_categories(category_id),
    CONSTRAINT chk_etexp_type CHECK (txn_type IN ('INCOME', 'EXPENSE')),
    CONSTRAINT chk_etexp_amt  CHECK (amount > 0),
    CONSTRAINT chk_etexp_del  CHECK (is_deleted IN ('Y', 'N'))
);


-- ============================================================
-- STEP 3: INDEXES
-- ============================================================

CREATE INDEX idx_etexp_user   ON et_expenses(user_id);
CREATE INDEX idx_etexp_date   ON et_expenses(txn_date);
CREATE INDEX idx_etexp_type   ON et_expenses(txn_type);
CREATE INDEX idx_etcat_user   ON et_categories(user_id);


-- ============================================================
-- STEP 4: PL/SQL PROCEDURES
-- ============================================================

-- -------------------------------------------------------
-- 4a. ADD_ET_USER — register a new user
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_et_user (
    p_username      IN  et_users.username%TYPE,
    p_email         IN  et_users.email%TYPE,
    p_password_hash IN  et_users.password_hash%TYPE,
    p_user_id       OUT et_users.user_id%TYPE
)
AS
BEGIN
    p_user_id := seq_et_users.NEXTVAL;

    INSERT INTO et_users (user_id, username, email, password_hash)
    VALUES (p_user_id, p_username, p_email, p_password_hash);

    COMMIT;

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20001, 'Username or email already exists.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_et_user;
/


-- -------------------------------------------------------
-- 4b. ADD_ET_CATEGORY — add a category for a user
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_et_category (
    p_user_id     IN  et_categories.user_id%TYPE,
    p_name        IN  et_categories.category_name%TYPE,
    p_type        IN  et_categories.category_type%TYPE,
    p_color       IN  et_categories.color_code%TYPE,
    p_cat_id      OUT et_categories.category_id%TYPE
)
AS
BEGIN
    p_cat_id := seq_et_categories.NEXTVAL;

    INSERT INTO et_categories (category_id, user_id, category_name, category_type, color_code)
    VALUES (p_cat_id, p_user_id, p_name, UPPER(p_type), p_color);

    COMMIT;

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20002, 'Category already exists for this user.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END add_et_category;
/


-- -------------------------------------------------------
-- 4c. ADD_ET_EXPENSE — add a new transaction
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_et_expense (
    p_user_id     IN  et_expenses.user_id%TYPE,
    p_category_id IN  et_expenses.category_id%TYPE,
    p_description IN  et_expenses.description%TYPE,
    p_amount      IN  et_expenses.amount%TYPE,
    p_type        IN  et_expenses.txn_type%TYPE,
    p_date        IN  et_expenses.txn_date%TYPE,
    p_expense_id  OUT et_expenses.expense_id%TYPE
)
AS
BEGIN
    p_expense_id := seq_et_expenses.NEXTVAL;

    INSERT INTO et_expenses (
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
END add_et_expense;
/


-- -------------------------------------------------------
-- 4d. DELETE_ET_EXPENSE — soft delete
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE delete_et_expense (
    p_expense_id  IN et_expenses.expense_id%TYPE,
    p_user_id     IN et_expenses.user_id%TYPE
)
AS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM et_expenses
    WHERE expense_id = p_expense_id
      AND user_id    = p_user_id
      AND is_deleted = 'N';

    IF v_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Expense not found or already deleted.');
    END IF;

    UPDATE et_expenses
    SET    is_deleted = 'Y'
    WHERE  expense_id = p_expense_id
      AND  user_id    = p_user_id;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END delete_et_expense;
/


-- -------------------------------------------------------
-- 4e. GET_ET_MONTHLY_SUMMARY — income, expense, balance
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE get_et_monthly_summary (
    p_user_id   IN  et_expenses.user_id%TYPE,
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
    FROM et_expenses
    WHERE user_id    = p_user_id
      AND is_deleted = 'N'
      AND EXTRACT(YEAR  FROM txn_date) = p_year
      AND EXTRACT(MONTH FROM txn_date) = p_month;

    p_balance := p_income - p_expense;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END get_et_monthly_summary;
/


-- ============================================================
-- STEP 5: VIEWS
-- ============================================================

CREATE OR REPLACE VIEW vw_et_expenses AS
SELECT
    e.expense_id,
    e.user_id,
    u.username,
    c.category_name,
    c.color_code,
    c.category_type,
    e.description,
    e.amount,
    e.txn_type,
    e.txn_date,
    EXTRACT(YEAR  FROM e.txn_date) AS txn_year,
    EXTRACT(MONTH FROM e.txn_date) AS txn_month,
    e.created_at
FROM  et_expenses   e
JOIN  et_users      u ON e.user_id     = u.user_id
JOIN  et_categories c ON e.category_id = c.category_id
WHERE e.is_deleted = 'N';


CREATE OR REPLACE VIEW vw_et_monthly_summary AS
SELECT
    user_id,
    EXTRACT(YEAR  FROM txn_date) AS txn_year,
    EXTRACT(MONTH FROM txn_date) AS txn_month,
    SUM(CASE WHEN txn_type = 'INCOME'  THEN amount ELSE 0 END) AS total_income,
    SUM(CASE WHEN txn_type = 'EXPENSE' THEN amount ELSE 0 END) AS total_expense,
    SUM(CASE WHEN txn_type = 'INCOME'  THEN amount ELSE -amount END) AS net_balance,
    COUNT(*) AS txn_count
FROM  et_expenses
WHERE is_deleted = 'N'
GROUP BY
    user_id,
    EXTRACT(YEAR  FROM txn_date),
    EXTRACT(MONTH FROM txn_date);


-- ============================================================
-- STEP 6: VERIFY EVERYTHING WAS CREATED
-- ============================================================

SELECT object_name, object_type, status
FROM user_objects
WHERE object_name LIKE 'ET_%'
   OR object_name LIKE 'SEQ_ET_%'
   OR object_name LIKE 'VW_ET_%'
ORDER BY object_type, object_name;

-- ============================================================
-- END OF SCHEMA
-- ============================================================
