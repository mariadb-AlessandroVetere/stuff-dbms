/* Year: 2013 */

#if !defined(_DATABASE_HPP_)
#define _DATABASE_HPP_

#include <sstream>

#include <cstdlib>
/* MySQL Connector */
#include <mysql/mysql.h>
#include <mysql/errmsg.h>
#include <mysql/mysqld_error.h>

#include <condition_variable>
#include <list>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <vector>
#include "buffer_string.h"

namespace Database
{
struct Conf
{
    std::string host;
    std::string user;
    std::string passwd;
    std::string db;
    unsigned short port;
    std::string unix_socket;

    Conf();

    template <typename XSDConfig>
    Conf& operator=(const XSDConfig& in);

    operator bool() const throw ()
    {
        return !host.empty() || !unix_socket.empty();
    }
};

static const int retry_count = 100;

class Connection;
typedef std::shared_ptr<Connection> Connection_var;

typedef std::runtime_error Exception;

static void init_thread() throw(Exception);
static void end_thread() throw();

class ConcatenableException: public Exception
{
public:
    ConcatenableException() : Exception("")
    {}

    using Exception::Exception;

    template <typename T>
    ConcatenableException&
    operator<<(T chunk)
    {
        std::ostringstream oss;
        oss << Exception::what() << chunk;
        *this = Exception(oss.str());
        return *this;
    }
};

class Error: public ConcatenableException
{
public:
    using ConcatenableException::ConcatenableException;

    Error(Connection* conn, const char* cmd) throw();

    Error(Connection_var conn, const char* cmd) throw() :
        Error(conn.get(), cmd)
    { }

    Error& operator<<(Conf& conf) throw();

    unsigned int err_no;
};

class LongValue
{
public:
    typedef Exception Error;

    LongValue(const char* str) throw() : str_(str)
    {}

    operator long() const throw(Error);

    operator unsigned long() const throw(Error)
    {
        return long(*this);
    }

    operator int() const throw(Error)
    {
        return long(*this);
    }

    operator unsigned int() const throw(Error)
    {
        return long(*this);
    }

    operator bool() const throw(Error)
    {
        return str_ ? long(*this) != 0 : false;
    }

private:
    const char* str_;
};

class Row
{
public:
    typedef Exception Error;

    Row() throw();
    Row(MYSQL_ROW row, unsigned int num_fields) throw();

    const char* operator [](unsigned int x) throw (Error);

    LongValue
    operator ()(unsigned int x) throw (Error)
    {
        return (*this)[x];
    }

    operator bool() const throw ()
    {
        return row_ != 0;
    }

private:
    MYSQL_ROW row_;
    unsigned int num_fields_;
};

class Result
{
public:
    Result(Connection_var conn, MYSQL_RES* res) throw();
    //Result(Connection* conn, MYSQL_RES* res) throw();
    ~Result() throw();

    Row fetch_row() throw(Error);
    unsigned int num_fields() const throw();
private:
    Connection_var conn_;
    MYSQL_RES* res_;
};

typedef std::shared_ptr<Result> Result_var;

class Connection
{
public:
    typedef Database::Exception Exception;
    typedef Exception NotConnected;

    class UnknownDatabase : public Error
    {
    public:
        UnknownDatabase(Connection* conn) : Error(conn, "mysql_real_connect")
        {}
    };

public:
    Connection() throw(Exception);
    ~Connection() throw();

    void connect(Conf& c, bool userdb = true) throw (Error, UnknownDatabase);

    void real_query(const buffer::string& q) throw (Error, NotConnected);
    Result_var use_result(Connection_var& conn) throw(Error);

    int next_result(Result_var& res) throw(Error);
    bool more_results() throw();
    unsigned int field_count() throw();

    unsigned int err_no() throw();
    const char* error() throw();
    bool err_fatal() throw();

    unsigned long real_escape_string(char* to, const buffer::string& from) const throw();

public:
    class Pool
    {
    private:
        typedef std::list<Connection_var> conn_list;

    public:
        class Entry
        {
            Entry(const Entry&) = delete;

        public:
            Entry() throw();
            Entry(Pool& pool) throw();
            ~Entry() throw();

            Connection_var operator ->() throw();
            Connection_var operator *() throw();
        private:
            Pool* pool_;
            Connection_var conn_;
        };

        Pool(size_t size) throw(Exception);
        void connect(Conf& c, bool userdb = true) throw(Error, UnknownDatabase);

        ~Pool() throw()
        {}

    protected:
        Connection_var acquire() throw();
        void release(Connection_var conn) throw();

        friend class Entry;

    private:
        typedef std::unique_lock<std::mutex> Guard;

        conn_list conns_;
        std::mutex mutex_;
        std::condition_variable cond_;
        size_t cond_waiters_;
    };

    typedef std::shared_ptr<Pool> Pool_var;

private:
    MYSQL* mysql_;
    bool connected_;
}; // class Connection


class Query
{
    Query(const Query&) = delete;

    const static size_t esc_reserve = 4096;

public:
    Query(Connection_var conn) throw (Database::Exception) :
        conn_(conn)
    {
        esc_buf_.reserve(esc_reserve);
    }

    Query(Connection::Pool& pool) throw (Database::Exception) :
        pool_entry_(pool),
        conn_(*pool_entry_)
    {
        esc_buf_.reserve(esc_reserve);
    }

    template <typename T>
    Query& operator<<(T query_chunk);

private:
    void build_query(std::string& q) throw ();
    void get_first_result() throw (Database::Error, Database::Exception);

public:
    void execute_only() throw (Database::Error, Database::Exception);
    Result_var execute() throw (Database::Error, Database::Exception);

    Row fetch_row() throw (Database::Error)
    {
        if (result_.get()) {
            return result_->fetch_row();
        }
        return Row();
    }


    buffer::string _esc(const buffer::string& in, bool quote = true) throw(std::bad_alloc);
    buffer::string esc(const char* in, bool quote = true) throw(std::bad_alloc);
    buffer::string esc(const std::string& in, bool quote = true) throw(std::bad_alloc);

    buffer::string
    esc(const buffer::string& in, bool quote = true) throw(std::bad_alloc)
    {
        if (in.length() == 0) {
            return quote ? buffer::string("''", 2) : buffer::string("");;
        }
        return _esc(in, quote);
    }

    buffer::string
    esc_or_null(const buffer::string& in) throw(std::bad_alloc)
    {
        if (in.length())
            return _esc(in);

        return buffer::string("NULL", 4);
    }

    // for tracing output
    operator const char*()
    {
        tmp_buf_ = query_.str();
        return tmp_buf_.c_str();
    }

    Connection_var& connection()
    {
        return conn_;
    }

private:
    Connection::Pool::Entry pool_entry_;
    Connection_var conn_;
    std::ostringstream query_;
    // escaping
    std::vector<char> esc_buf_;

    Result_var result_;

    // tracing
    std::string tmp_buf_;
}; // class Query
} // namespace Database


#if 0
#define __LOG_RETRY(CONN, I, LEVEL) \
  if (CONN->logger() && CONN->logger()->log_level() >= LEVEL) \
  { \
    CONN->logger()->stream(LEVEL) << FNS \
      << CONN << " retry " << i \
      << " due to MySQL error " \
      << CONN->err_no(); \
  }

#define _LOG_RETRY(CONN, I) __LOG_RETRY(CONN, I, Logging::Logger::DEBUG)

#define LOG_RETRY(I) _LOG_RETRY(this, I)
#else
#define __LOG_RETRY(CONN, I, LEVEL)
#define _LOG_RETRY(CONN, I)
#define LOG_RETRY(I)
#endif

namespace Database
{
inline
Conf::Conf() :
    port(0)
{ }

template <typename XSDConfig>
Conf&
Conf::operator=(const XSDConfig& in)
{
    host = in.host();
    user = in.user();
    passwd = in.passwd();
    db = in.db();
    port = in.port();
    unix_socket = in.unix_socket();
    return *this;
}


inline
static void
init_thread() throw(Exception)
{
    if (mysql_thread_init()) {
        throw Exception("MySQL thread init failed!");
    }
}

inline
static void
end_thread() throw()
{
    mysql_thread_end();
}


inline
Error::Error(Connection* conn, const char* cmd) throw()
    : err_no(conn->err_no())
{
    std::ostringstream oss;
    oss << cmd << ": " << conn->error() <<
        "(" << conn->err_no() << ")";
    *static_cast<Exception *>(this) = Exception(oss.str());
}

inline
Error&
Error::operator<<(Conf& conf) throw()
{
    std::ostringstream oss;
    oss << Exception::what();
    if (!conf.host.empty())
        oss << ";\nhost: '" << conf.host;
    if (conf.port)
        oss << "';\nport: '" << conf.port;
    if (!conf.unix_socket.empty())
        oss << "';\nsocket: '" << conf.unix_socket;
    if (!conf.db.empty())
        oss << "';\ndb: '" << conf.db;
    if (!conf.user.empty())
        oss << "';\nuser: '" << conf.user;
    oss << "'";
    *static_cast<Exception *>(this) = Exception(oss.str());
    return *this;
}


inline
Row::Row() throw() :
    row_(0),
    num_fields_(0)
{ }

inline
Row::Row(MYSQL_ROW row, unsigned int num_fields) throw() :
    row_(row),
    num_fields_(num_fields)
{ }

inline
const char*
Row::operator [](unsigned int x) throw (Error)
{
    if (x >= num_fields_) {
        throw Error("Wrong field index"); // TODO
    }

    return row_[x];
}

inline
LongValue::operator long() const throw (Error)
{
    char* tailptr = 0;
    if (!str_) {
        throw Error("Empty value in field index"); // TODO
    }

    long l = strtol(str_, &tailptr, 10);

    if (*tailptr) {
        throw Error("Not an integer in field index"); // TODO
    }

    return l;
}


inline
Result::Result(Connection_var conn, MYSQL_RES* res) throw() :
    conn_(conn),
    res_(res)
{ }

#if 0
inline
Result::Result(Connection* conn, MYSQL_RES* res) throw() :
    conn_(conn),
    res_(res)
{}
#endif

inline
Result::~Result() throw()
{
    mysql_free_result(res_);
}

inline
Row
Result::fetch_row() throw(Error)
{
    MYSQL_ROW row = 0;

    for (int i = 0; true; ++i) {
        row = mysql_fetch_row(res_);
        if (row) {
            return Row(row, num_fields());
        }

        if (conn_->err_no() == 0) {
            return Row();
        }

        if (conn_->err_fatal() || i >= retry_count) {
            throw Error(conn_, "mysql_fetch_row");
        }

        _LOG_RETRY(conn_, i);
    }
}

inline
unsigned int
Result::num_fields() const throw()
{
    return mysql_num_fields(res_);
}


inline
Connection::Connection() throw(Exception) :
    connected_(false)
{
    if (!mysql_thread_safe() /* FIXME: this should be done in singleton */) {
        throw Exception("MySQL library not thread safe!");
    }
    mysql_ = mysql_init(0);

    my_bool my_true = 1;
    mysql_options(mysql_, MYSQL_OPT_RECONNECT, &my_true);
}

inline
Connection::~Connection() throw()
{
    mysql_close(mysql_);
}

inline
void
Connection::connect(Conf& c, bool userdb)
throw (Error, UnknownDatabase)
{
    if (!mysql_real_connect(
        mysql_,
        c.host.c_str(),
        c.user.c_str(),
        c.passwd.c_str(),
        (userdb ? c.db.c_str() : 0),
        c.port,
        c.unix_socket.c_str(), CLIENT_MULTI_STATEMENTS)) {
        if (err_no() == ER_BAD_DB_ERROR) {
            throw UnknownDatabase(this);
        }
        throw Error(this, "mysql_real_connect") << c;
    }
    connected_ = true;
}


inline
void
Connection::real_query(const buffer::string& q)
throw (Error, NotConnected)
{
    if (!connected_) {
        throw NotConnected("Connection::real_query(): not connected");
    }
    for (int i = 0; true; ++i) {
        if (mysql_real_query(mysql_, q.data(), q.length()) == 0) {
            return;
        }

        if (err_fatal() || i >= retry_count) {
            throw Error(this, "mysql_real_query");
        }

        LOG_RETRY(i);
    }
}


inline
Result_var
Connection::use_result(Connection_var &conn) throw(Error)
{
    MYSQL_RES* res = 0;

    for (int i = 0; true; ++i) {
        res = mysql_use_result(mysql_);

        if (res) {
            return std::make_shared<Result>(conn, res);
        }
        if (field_count() == 0) {
            return Result_var();
        }

        if (err_fatal() || i >= retry_count) {
            throw Error(this, "mysql_use_result");
        }

        LOG_RETRY(i);
    }
}


inline
int
Connection::next_result(Result_var& prev_res) throw(Error)
{
    /* MySQL API glitch */
    if (!mysql_more_results(mysql_)) {
        return -1;
    }

    int res = 0;
    /*
       according to 20.7.3.46:
        "... Before each call to mysql_next_result(), you must call
         mysql_free_result() for the current statement if it is a statement
         that returned a result set (rather than just a result status)."
     */
    prev_res.reset();

    for (int i = 0; true; ++i) {
        res = mysql_next_result(mysql_);
        if (res <= 0) {
            return res;
        }

        if (err_fatal() || i >= retry_count) {
            throw Error(this, "mysql_next_result");
        }

        LOG_RETRY(i);
    }
}

inline
bool
Connection::more_results() throw()
{
    return mysql_more_results(mysql_) != 0;
}

inline
unsigned int
Connection::field_count() throw()
{
    return mysql_field_count(mysql_);
}

inline
unsigned int
Connection::err_no() throw()
{
    return mysql_errno(mysql_);
}

inline
const char*
Connection::error() throw()
{
    return mysql_error(mysql_);
}

inline
bool
Connection::err_fatal() throw()
{
    unsigned int err = err_no();
    return err != CR_SERVER_LOST
        && err != CR_SERVER_GONE_ERROR
        && err != ER_LOCK_DEADLOCK
        /* Sometimes 'exit handler for duplicate error' (see find_or_add function)
           does not work correctly (supposedly due to racing between AUTO_INCREMENT lock and write lock).
           In this case 'select id ... for update' will return NULL.
        */
        && err != ER_BAD_NULL_ERROR
        /* Again, sometimes 'exit handler for duplicate error' (see find_or_add function)
           does not work correctly (supposedly due to bug #5889).
           In this case transaction will fail with 1062 (ER_DUP_ENTRY).
        */
        && err != ER_DUP_ENTRY;
}

inline
unsigned long
Connection::real_escape_string(char* to, const buffer::string& from) const throw()
{
    return mysql_real_escape_string(mysql_, to, from.data(), from.length());
}


inline
Connection::Pool::Entry::Entry() throw() :
    pool_(0)
{ }

inline
Connection::Pool::Entry::Entry(Connection::Pool& pool) throw() :
    pool_(&pool),
    conn_(pool_->acquire())
{ }

inline
Connection::Pool::Entry::~Entry() throw()
{
    if (pool_) {
        pool_->release(conn_);
    }
}

inline
Connection_var
Connection::Pool::Entry::operator ->() throw()
{
    return conn_;
}

inline
Connection_var
Connection::Pool::Entry::operator *() throw()
{
    return conn_;
}


inline
Connection::Pool::Pool(size_t size) throw(Connection::Exception) :
    cond_waiters_(0)
{
    for (size_t i = 0; i < size; ++i) {
        conns_.push_back(std::make_shared<Connection>());
    }
}

inline
void
Connection::Pool::connect(Conf& c, bool userdb) throw(Error, UnknownDatabase)
{
    for (conn_list::iterator i = conns_.begin(); i != conns_.end(); ++i) {
        (*i)->connect(c, userdb);
    }
}

inline
Connection_var
Connection::Pool::acquire() throw()
{
    Guard guard(mutex_);

    // wait until connection pool is non-empty
    while (conns_.empty()) {
        ++cond_waiters_;
        cond_.wait(guard);
        --cond_waiters_;
    }

    // get the first connection from list
    Connection_var res = conns_.front();
    // .. and remove it
    conns_.erase(conns_.begin());

    return res;
}

inline
void
Connection::Pool::release(Connection_var conn) throw()
{
    Guard guard(mutex_);

    // insert released connection at the front of the list
    // (to be honest, it is NOT important where we insert the new pool entry)
    conns_.insert(conns_.begin(), conn);

    // signal the condition
    if (cond_waiters_) {
        cond_.notify_one();
    }
}

template <typename T>
Query& Query::operator<<(T query_chunk)
{
    query_ << query_chunk;
    return *this;
}

inline
void
Query::build_query(std::string& q) throw ()
{
    // data copied here?
    // Hope, no - v3 string uses COW
    q = query_.str();

#if 0
      if (logger() && logger()->log_level() >= Logging::Logger::TRACE)
      {
        logger()->stream(Logging::Logger::TRACE, "<ASPECT>")
          << caller << "(): executing SQL: \n" << q;
      }
#endif

    query_.clear();
    query_.str("");
    result_.reset();
}

inline
void
Query::get_first_result() throw (Database::Error, Database::Exception)
{
    do {
        result_ = conn_->use_result(conn_);
    } while (!result_ && conn_->next_result(result_) == 0);
}

inline
void
Query::execute_only() throw (Database::Error, Database::Exception)
{
    std::string q;
    build_query(q);
    conn_->real_query(q);
    get_first_result();
}

inline
Result_var
Query::execute() throw (Database::Error, Database::Exception)
{
    std::string q;
    build_query(q);

    for (int i = 0; true; ++i) {
        conn_->real_query(q);

        get_first_result();

        if (result_) {
            return result_;
        }

        if (i >= retry_count) {
            throw Exception("Empty resultset!");
        }
    }
}

inline
buffer::string
Query::_esc(const buffer::string& in, bool quote) throw(std::bad_alloc)
{
    // TODO: instead make ostream modifier, f.ex.:
    // ... << Database::esc << ...
    size_t end = esc_buf_.size();
    esc_buf_.resize(end + in.size() * 2 + 3);
    char* out = (char *)&esc_buf_[end];
    unsigned long out_l = 0;
    if (quote)
        out[out_l++] = '\'';
    out_l += conn_->real_escape_string(out + out_l, in);
    if (quote)
        out[out_l++] = '\'';
    esc_buf_.resize(end + out_l);
    return buffer::string(out, out_l);
}

inline
buffer::string
Query::esc(const char* in, bool quote) throw(std::bad_alloc)
{
    return esc(buffer::string(in), quote);
}

inline
buffer::string
Query::esc(const std::string& in, bool quote) throw(std::bad_alloc)
{
    return esc(buffer::string(in.data(), in.size()), quote);
}
}

#undef __LOG_RETRY
#undef _LOG_RETRY
#undef LOG_RETRY

#endif // _DATABASE_HPP_
