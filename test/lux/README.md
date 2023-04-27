# LUX tests

`__*` are special directories, such as include directories `__common`, helper directories `__skeleton`.

Other directories contain test volumes, e.g. `grpc-api-lg.service.router.RegistryService`, `http-api`. Each test volume directory contains test group directory, such as `grpc-api-lg.service.router.RegistryService/01-RegisterVirtualService`. Test group directory contains LUX tests that can be treated as test cases.

To create a new test, copy the `__skeleton` directory and use it as a test group, e.g.
```
$ mkdir -p http-api
$ cp -R __skeleton http-api/01-SomeTestGroup
```

Do not forget to remove the skip-related lines from the skeleton test case.

## Running LUX tests

To run LUX tests, run the following command from the project root: `make lux-tests`.

To run a single test, run: `TEST=<path-to-test-case> make lix-tests`, e.g.

```bash
$ TEST=tests/lux/grpc-api-lg.service.router.RegistryService/01-RegisterVirtualService/02-invalid-package.lux make lux-tests
```

After the run, several directories will be located inside each test group directory:

- `lux_logs`: LUX logs, containing every bit of information regarding the test run;
- `router_logs`: router logs, containing the application logs, one directory per test case, named after the test case, e.g. `router_logs/02-invalid-package/`;
- `json`: request and response bodies.

## Cleaning up LUX runs

To clean everything up after testing is done, run `make lux-clean`.

_**NB**: `lux-clean` target cleans up everything related to the LUX run, including LUX logs, router logs, JSON responses, etc._
