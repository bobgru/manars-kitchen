## 1. Server Modules

- [x] 1.1 Create `server/Server/Api.hs` with the Servant API type definition (20 endpoints under `/api/`)
- [x] 1.2 Create `server/Server/Json.hs` with orphan ToJSON/FromJSON instances for domain types and request/response DTOs
- [x] 1.3 Create `server/Server/Error.hs` with `ApiError` ADT and `throwApiError` mapping to Servant error responses with JSON bodies
- [x] 1.4 Create `server/Server/Handlers.hs` with thin handler wrappers calling service-layer functions

## 2. Server Executable

- [x] 2.1 Create `server/Main.hs` with Warp startup, argument parsing for database path and port
- [x] 2.2 Add `manars-server` executable stanza to `manars-kitchen.cabal` with dependencies (servant, servant-server, warp, wai, aeson, text, containers, time, bytestring, http-types)

## 3. API Test Suite

- [x] 3.1 Add `server` to test-suite `hs-source-dirs` and add test dependencies (servant, servant-server, servant-client, warp, http-client, http-types, text) to `manars-kitchen.cabal`
- [x] 3.2 Create `test/ApiSpec.hs` with servant-client functions derived from the API type, `withTestApp`/`withSeededApp` helpers, and 19 tests covering read endpoints, error responses, draft lifecycle, calendar, and absence lifecycle
- [x] 3.3 Register `ApiSpec` in `test/Spec.hs`
- [x] 3.4 Fix all compiler warnings (unused imports, missing type signatures, name shadowing) for clean `stack clean && stack test` build
