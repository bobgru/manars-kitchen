.RECIPEPREFIX = >

.PHONY: clean build test run demo fast-demo server web

build:
> stack build

test:
> stack test

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
