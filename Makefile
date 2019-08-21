EXTENSION = pgmock
DATA = pgmock--0.2.sql
REGRESS = extension $(shell ls -p sql/ | grep -v / | sed "s/\.sql//" | sed "s/\bextension\b//")

# postgres build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)