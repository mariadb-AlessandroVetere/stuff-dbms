#include <iostream>
#include "Database.hpp"

const size_t pool_size = 10;

using namespace Database;

int main(int argc, char *argv[])
{
    Conf c;
    {
        c.host = argc < 3 ? "localhost" : argv[2];
        c.port = 3306;
        /* Or: */
        // c.unix_socket = "/var/run/mysqld/mysqld.sock";
    }
    c.user = "root";
    c.passwd = "a";
    c.db = "INFORMATION_SCHEMA";

    Connection::Pool pool(pool_size);
    try {
        pool.connect(c);
    } catch (Database::Error &ex) {
        std::cerr << ex.what();
    }

    try {
        std::string lang(argc > 1 ? argv[1] : "");
        Query q(pool);
        q << "-- any SQL code (multiple SQL statements allowed)\n"
            "select MAXLEN, CHARACTER_SET_NAME, DEFAULT_COLLATE_NAME, DESCRIPTION"
            " from CHARACTER_SETS";
        if (lang.empty())
            q << ";";
        else
            q << " where DEFAULT_COLLATE_NAME like '%" << lang << "%';";

        q.execute(); // or q.execute_only() if no data returned
        Row row;
        while (row = q.fetch_row()) {
            int maxlen = row(0); // integers are accessed with ()
            std::string charset = row[1]; // strings are accessed with []
            std::string def_colname = row[2];
            std::string descr = row[3];
            std::cout << maxlen << " " << charset << " " << def_colname << " (" << descr << ")" << std::endl;
        }
    } catch (Database::Error &ex) {
        std::cerr << ex.what();
    } catch (Database::Exception &ex) {
        std::cerr << ex.what();
    }
}
