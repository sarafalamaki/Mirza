# Mirza

## Setting up

If you do not have the latest version of stack, please remove whatever version of stack you have:

`sudo apt remove haskell-stack`

Then get the latest version of stack by running:

`wget -qO- https://get.haskellstack.org/ | sh`

## Building the server

To build the server, run:

`stack build`

## Installing PostgreSQL

PostgreSQL is used as the database backend. Before you run the server, make sure you have PostgreSQL 9 or higher installed.

To install, you can follow the instructions [here]( http://yallalabs.com/linux/how-to-install-and-use-postgresql-10-on-ubuntu-16-04/).

Note that you may need to run the commands as a super user.

Create a Postgres account.
There are good instructions [here](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-postgresql-on-ubuntu-16-04)

Type in `psql` and see that you can open up a `psql` shell.

## Initalising the database

When first run you will need to inialise the database.

After that, to create the database, run:
`createdb 'devsupplychainserver'`

To initalise the database run:
`stack exec supplyChainServer -- --orhost localhost --orport 8200 --init-db -c "dbname=<database name>"`

The `-c` option takes a database connection string in [libpq format](https://www.postgresql.org/docs/9.5/static/libpq-connect.html#LIBPQ-CONNSTRING).

Some examples are:

- "dbname=devsupplychainserver"`
- "postgresql://localhost/devsupplychainserver"

The default connection string is `dbname=devsupplychainserver`.

## Running the server

Finally, to run the server, do:

`stack exec supplyChainServer -- --orhost localhost --orport 8200`

Then you can check out the API at:

<http://localhost:8000/swagger-ui/>

To use ghci interactively, run

`stack ghci`

If you find yourself deleting and recreating the database frequently, run
`./restart.sh`. It will build your code, drop the database
`devsupplychainserver`, create it anew and run the migration script
to create all the relevant tables.

To do a clean build instead, do `./restart.sh --clean`.

## Running the tests

The `run_tests.sh` script will run the tests (and makes sure they run single
threaded because the tests depend on previous tests), it should usually be run
as:

```shell
./run_tests.sh

# If you want a coverage report
./coverage.sh

# If you want to launch the report in the browser
./coverage.sh --launch
```

## To initialise the OR test DB, run the following:

```shell
stack build --fast && dropdb testorgregistry && createdb testorgregistry && stack exec orgRegistry -- -c 'dbname=testorgregistry' --env Dev --log-level DebugS initdb
```

You'll need to run the above each time the OR db schema changes.

## Acronyms

Some common acronyms used in the project.

**SCS**: Supply Chain Service

**OR**:  Org Registry

## Known Issues/Notes

- The time precision stored in the database is in microseconds, and Haskell timestamps are precise up to a nanosecond. When submitting a JWK, the time fields in the key (expiry time, revocation time) is accepted if it's within 1 second of the current time.

### Useful Tools

- [GS1 Company Database](https://www.gs1us.org/tools/gs1-company-database-gepir) - You can search for GLN (Global Location Number) of GS1 Companies here
