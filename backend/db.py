import oracledb
from config import DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, DB_SERVICE

def get_connection():
    conn = oracledb.connect(
        user     = DB_USER,
        password = DB_PASSWORD,
        dsn      = f"{DB_HOST}:{DB_PORT}/{DB_SERVICE}"
    )
    return conn