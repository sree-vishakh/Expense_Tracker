from flask import Flask, request, jsonify
from flask_cors import CORS
from db import get_connection
import oracledb

app = Flask(__name__)
CORS(app)

# ─────────────────────────────────────────
# GET /api/expenses?user_id=1&year=2025&month=3
# ─────────────────────────────────────────
@app.route("/api/expenses", methods=["GET"])
def get_expenses():
    user_id = request.args.get("user_id")
    year    = request.args.get("year")
    month   = request.args.get("month")

    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    try:
        conn   = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT expense_id, category_name, color_code,
                   description, amount, txn_type, txn_date
            FROM   vw_et_expenses
            WHERE  user_id = :user_id
        """
        params = {"user_id": user_id}

        if year and month:
            query += " AND txn_year = :year AND txn_month = :month"
            params["year"]  = year
            params["month"] = month

        query += " ORDER BY txn_date DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()

        expenses = []
        for row in rows:
            expenses.append({
                "expense_id":    row[0],
                "category_name": row[1],
                "color_code":    row[2],
                "description":   row[3],
                "amount":        float(row[4]),
                "txn_type":      row[5],
                "txn_date":      row[6].strftime("%Y-%m-%d")
            })

        cursor.close()
        conn.close()
        return jsonify(expenses), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────
# POST /api/expenses
# ─────────────────────────────────────────
@app.route("/api/expenses", methods=["POST"])
def add_expense():
    data = request.get_json()

    required = ["user_id", "category_id", "description", "amount", "txn_type", "txn_date"]
    for field in required:
        if field not in data:
            return jsonify({"error": f"{field} is required"}), 400

    try:
        conn   = get_connection()
        cursor = conn.cursor()

        expense_id_var = cursor.var(oracledb.NUMBER)

        from datetime import datetime
        txn_date = datetime.strptime(data["txn_date"], "%Y-%m-%d")

        cursor.callproc("add_et_expense", [
            data["user_id"],
            data["category_id"],
            data["description"],
            data["amount"],
            data["txn_type"],
            txn_date,
            expense_id_var
        ])

        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({
            "message":    "Expense added successfully",
            "expense_id": int(expense_id_var.getvalue())
        }), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────
# DELETE /api/expenses/<expense_id>?user_id=1
# ─────────────────────────────────────────
@app.route("/api/expenses/<int:expense_id>", methods=["DELETE"])
def delete_expense(expense_id):
    user_id = request.args.get("user_id")

    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    try:
        conn   = get_connection()
        cursor = conn.cursor()

        cursor.callproc("delete_et_expense", [expense_id, user_id])

        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({"message": "Expense deleted successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────
# GET /api/summary?user_id=1&year=2025&month=3
# ─────────────────────────────────────────
@app.route("/api/summary", methods=["GET"])
def get_summary():
    user_id = request.args.get("user_id")
    year    = request.args.get("year")
    month   = request.args.get("month")

    if not all([user_id, year, month]):
        return jsonify({"error": "user_id, year and month are required"}), 400

    try:
        conn   = get_connection()
        cursor = conn.cursor()

        income_var  = cursor.var(oracledb.NUMBER)
        expense_var = cursor.var(oracledb.NUMBER)
        balance_var = cursor.var(oracledb.NUMBER)

        cursor.callproc("get_et_monthly_summary", [
            user_id, year, month,
            income_var, expense_var, balance_var
        ])

        cursor.close()
        conn.close()

        return jsonify({
            "income":  float(income_var.getvalue()  or 0),
            "expense": float(expense_var.getvalue() or 0),
            "balance": float(balance_var.getvalue() or 0)
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────
# GET /api/categories?user_id=1
# ─────────────────────────────────────────
@app.route("/api/categories", methods=["GET"])
def get_categories():
    user_id = request.args.get("user_id")

    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    try:
        conn   = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT category_id, category_name, category_type, color_code
            FROM   et_categories
            WHERE  user_id = :user_id
            ORDER BY category_name
        """, {"user_id": user_id})

        rows = cursor.fetchall()
        categories = [
            {
                "category_id":   row[0],
                "category_name": row[1],
                "category_type": row[2],
                "color_code":    row[3]
            }
            for row in rows
        ]

        cursor.close()
        conn.close()
        return jsonify(categories), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────
# Health check
# ─────────────────────────────────────────
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "message": "Expense Tracker API running"}), 200


if __name__ == "__main__":
    app.run(debug=True, port=5000)