.RECIPEPREFIX = >

.PHONY: clean build test unit-test integration-test run demo fast-demo server web

build:
> stack build

test: unit-test integration-test

unit-test:
> stack test manars-kitchen:test:manars-kitchen-unit-test

integration-test:
> stack test manars-kitchen:test:manars-kitchen-integration-test

run: build
> @mkdir -p run-db
> stack exec manars-cli

demo: build
> @mkdir -p demo-db
> stack exec manars-cli -- --demo demo/restaurant-setup.txt

fast-demo: build
> @mkdir -p demo-db
> stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay

clean:
> rm -f demo-db/*.db demo-db/*.db-wal demo-db/*.db-shm
> stack clean

server: build
> stack run manars-server -- run-db/manars-kitchen.db

web:
> cd web && npm install && npm run build
