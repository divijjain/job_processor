# JobProcessor

An HTTP service that takes a job (a list of tasks with shell commands and dependencies)
and returns the tasks in an order where every task runs after the tasks it requires.
Tasks keep their input order unless a dependency forces them later.

## Running

```sh
mix setup
mix phx.server        # listens on localhost:4000
mix test
mix precommit         # format, credo --strict, dialyzer, tests with a 90% coverage minimum
```

## API

Both endpoints take the same JSON body. It is parsed as JSON even when the request has no
content type, or is sent as a form (`curl -d` without `-H 'content-type: application/json'`).

The challenge's sample input, used in the commands below (save it as `job.json`):

```json
{
  "tasks": [
    { "name": "task-1", "command": "touch /tmp/file1" },
    { "name": "task-2", "command": "cat /tmp/file1", "requires": ["task-3"] },
    { "name": "task-3", "command": "echo 'Hello World!' > /tmp/file1", "requires": ["task-1"] },
    { "name": "task-4", "command": "rm /tmp/file1", "requires": ["task-2", "task-3"] }
  ]
}
```

### `POST /jobs`: tasks in execution order (JSON)

```sh
curl -X POST localhost:4000/jobs -d @job.json
```

Output for the sample input (`200`):

```json
{
  "tasks": [
    { "name": "task-1", "command": "touch /tmp/file1" },
    { "name": "task-3", "command": "echo 'Hello World!' > /tmp/file1" },
    { "name": "task-2", "command": "cat /tmp/file1" },
    { "name": "task-4", "command": "rm /tmp/file1" }
  ]
}
```

### The job as a bash script

Ask for it in any of these ways. The output can be piped straight into bash:

```sh
# dedicated path
curl -X POST localhost:4000/jobs/script -d @job.json | bash

# content negotiation on /jobs
curl -X POST localhost:4000/jobs -H 'accept: text/plain' -d @job.json

# query parameter on /jobs (sh or bash; json forces JSON)
curl -X POST 'localhost:4000/jobs?format=bash' -d @job.json
```

| Request | Content type of the script |
|---|---|
| `Accept: text/x-shellscript`, `text/x-sh`, `application/x-sh` or `application/x-shellscript` | `text/x-shellscript` |
| `Accept: text/plain` | `text/plain` |
| `?format=sh`, `?format=bash` or `?_format=sh` | `text/x-shellscript` |
| `POST /jobs/script` with no `Accept` header or `*/*` | `text/x-shellscript` |

`/jobs` returns JSON when the client accepts anything (`*/*` or no `Accept` header), and
`406` when it accepts neither JSON nor a script.

The script is exactly the format the challenge shows: a shebang, then one command per line,
each passed through verbatim. Output for the sample input (`200`):

```bash
#!/usr/bin/env bash
touch /tmp/file1
echo 'Hello World!' > /tmp/file1
cat /tmp/file1
rm /tmp/file1
```

### Errors

Invalid jobs return `422`. Every error has the same envelope under `errors`: a `type`
to branch on (`validation` or `cycle`), a human-readable `detail`, and data for that type.

- **`validation`**: errors keyed by field, as Phoenix's `ChangesetJSON` renders them. `tasks`
  has one entry per task, by position, with `{}` for a valid task. Checked: `tasks` present and
  a list, `name` and `command` required strings, `requires` a list of strings, unique names,
  known dependencies, no task requiring itself. All errors are reported at once.
- **`cycle`**: `cycle` is one loop as a path where each task requires the next; `unscheduled`
  is every task that could not run (the loop and anything waiting on it), in input order.

When a script was requested, the error is a script too, so `curl ... | bash` fails loudly
instead of running anything: it prints the JSON error to stderr and exits 1.

See examples 4 to 7 below for real outputs.

### Status codes

| Status | When | Body |
|---|---|---|
| `200` | The job was planned | The tasks as JSON, or the script |
| `400` | The body is not valid JSON | `{"errors": {"detail": "Bad Request"}}` |
| `404` | Any other path or method (only `POST /jobs` and `POST /jobs/script` exist) | `{"errors": {"detail": "Not Found"}}` |
| `406` | The `Accept` header or `?format=` allows neither JSON nor a script | `{"errors": {"detail": "Not Acceptable"}}` |
| `422` | The job is invalid or has a dependency cycle | The error envelope above, as JSON or a failing script |
| `500` | An unexpected server error | `{"errors": {"detail": "Internal Server Error"}}` |

`422` is the only error the application produces itself, through `FallbackController` (see
[Request flow](#request-flow)). The others are raised before or outside the controller and
rendered by Phoenix's `ErrorJSON`, always as JSON, even when a script was requested. Their
bodies are fixed text with no request input in them, so piping one into bash fails (exit 127)
without running anything. In development (`debug_errors: true`), Phoenix shows its debug page
for these instead.

## Examples

Real outputs from the running server, for each input. JSON is pretty-printed (key order as
sent); scripts are shown byte for byte.

### 1. The challenge's sample

Shown above: `task-3` moves ahead of `task-2`, which requires it; `task-1` and `task-4` stay
where they are.

### 2. Independent tasks keep their input order

```json
{"tasks": [
  {"name": "lint", "command": "mix credo"},
  {"name": "format", "command": "mix format --check-formatted"},
  {"name": "test", "command": "mix test"}
]}
```

`POST /jobs` → `200`:

```json
{
  "tasks": [
    { "name": "lint", "command": "mix credo" },
    { "name": "format", "command": "mix format --check-formatted" },
    { "name": "test", "command": "mix test" }
  ]
}
```

### 3. Shared requirements (diamond)

`deploy` needs `build` and `migrate`, which both need `fetch`. Listed in reverse:

```json
{"tasks": [
  {"name": "deploy", "command": "./deploy.sh", "requires": ["build", "migrate"]},
  {"name": "migrate", "command": "mix ecto.migrate", "requires": ["fetch"]},
  {"name": "build", "command": "mix release", "requires": ["fetch"]},
  {"name": "fetch", "command": "mix deps.get"}
]}
```

`POST /jobs` → `200`. `fetch` runs once, first; `migrate` stays ahead of `build` because it was
listed first:

```json
{
  "tasks": [
    { "name": "fetch", "command": "mix deps.get" },
    { "name": "migrate", "command": "mix ecto.migrate" },
    { "name": "build", "command": "mix release" },
    { "name": "deploy", "command": "./deploy.sh" }
  ]
}
```

`POST /jobs/script` → `200`:

```bash
#!/usr/bin/env bash
mix deps.get
mix ecto.migrate
mix release
./deploy.sh
```

### 4. A cycle

`a → c → b → a` is a loop; `d` waits on it; `e` is unaffected but nothing runs when the job
is rejected:

```json
{"tasks": [
  {"name": "a", "command": "echo a", "requires": ["c"]},
  {"name": "b", "command": "echo b", "requires": ["a"]},
  {"name": "c", "command": "echo c", "requires": ["b"]},
  {"name": "d", "command": "echo d", "requires": ["a"]},
  {"name": "e", "command": "echo e"}
]}
```

`POST /jobs` → `422`:

```json
{
  "errors": {
    "type": "cycle",
    "cycle": ["a", "c", "b", "a"],
    "unscheduled": ["a", "b", "c", "d"],
    "detail": "dependency cycle detected"
  }
}
```

### 5. The same cycle, as a script

`POST /jobs/script` → `422`:

```bash
#!/usr/bin/env bash
printf '%s\n' 'job rejected: dependency cycle detected' >&2
printf '%s\n' '{"errors":{"type":"cycle","cycle":["a","c","b","a"],"unscheduled":["a","b","c","d"],"detail":"dependency cycle detected"}}' >&2
exit 1
```

Piped into bash, it runs nothing, prints both lines to stderr, and exits with status 1.

### 6. Validation errors

A duplicate name, a missing command, an unknown requirement, and a task requiring itself:

```json
{"tasks": [
  {"name": "a", "command": "echo a"},
  {"name": "b", "requires": ["x"]},
  {"name": "a", "command": "echo again"},
  {"name": "c", "command": "echo c", "requires": ["c"]}
]}
```

`POST /jobs` → `422`, one entry per task in input order:

```json
{
  "errors": {
    "type": "validation",
    "tasks": [
      { "name": ["is used by more than one task"] },
      { "command": ["can't be blank"], "requires": ["references unknown task \"x\""] },
      { "name": ["is used by more than one task"] },
      { "requires": ["cannot include the task itself"] }
    ],
    "detail": "validation failed"
  }
}
```

### 7. No tasks

```json
{}
```

`POST /jobs` → `422`:

```json
{ "errors": { "type": "validation", "tasks": ["can't be blank"], "detail": "validation failed" } }
```

## Layout

| Module | Role |
|---|---|
| `JobProcessor` | Public API (`plan/1`, `script/1`) |
| `JobProcessor.Job`, `JobProcessor.JobTask` | Parse and validate the request (Ecto embedded schemas) |
| `JobProcessor.Sorter` | Stable topological sort (Kahn's algorithm) and cycle detection |
| `JobProcessor.Script` | Render ordered tasks as bash |
| `JobProcessorWeb.JobController` | HTTP endpoints; errors go to `FallbackController` |
| `JobProcessorWeb.JobJSON`, `JobProcessorWeb.JobSH` | Render responses and errors as JSON or bash (errors as a failing script) |

### Request flow

```
POST /jobs, POST /jobs/script
  │
  ├─ Endpoint      parses the body (as JSON when no content type is given)    → 400 if malformed
  ├─ Router        :format_param maps ?format=; :accepts picks json, sh or txt → 404 / 406
  ├─ JobController create/2 calls JobProcessor.plan/1
  │     ├─ {:ok, tasks}  → render(:create)  via JobJSON (json) or JobSH (sh, txt)  → 200
  │     └─ {:error, _}   → returned to action_fallback
  └─ FallbackController
        ├─ %Ecto.Changeset{}  → render(:error) via ChangesetJSON or JobSH   → 422
        └─ {:cycle, details}  → render(:cycle) via JobJSON or JobSH         → 422
```

The controller only handles success. `action_fallback JobProcessorWeb.FallbackController`
sends anything else the action returns to `FallbackController.call/2`, which sets the status
and picks the view for the negotiated format (`put_view(json: ..., sh: JobSH, txt: JobSH)`),
the same way the controller does for success. Every way a job can be rejected is handled in
that one module, and each error type is a clause there.

## Design notes

**Stable order.** The sort is Kahn's algorithm with a priority queue (`:gb_sets`) keyed by
input position, so each step runs the earliest-listed task whose requirements are done. Tasks
keep their input order unless a dependency forces them later, and the same job always produces
the same output. OTP's `:digraph_utils.topsort/1` would be less code, but its order for
unconstrained tasks is arbitrary: given `install, configure, build, test, lint` (where `build`
requires the first two and `test` requires `build`), it returns
`lint, configure, install, build, test`. Runs in O(n log n).

**Cycles are reported as a path.** When tasks remain unscheduled, each of them must have an
unscheduled requirement, so following requirements from any of them must revisit a task.
The loop found that way (`a -> b -> a`) is what the client needs to fix; tasks merely waiting
behind it are listed separately as `unscheduled`.

**Script errors cannot run code.** Error messages echo request input, such as an unknown task
name. Sent as JSON to a client piping into bash, a name like `$(rm -rf ~)` inside JSON's double
quotes would be executed. Errors in the `sh` format are therefore scripts that single-quote
every value (where bash expands nothing) and `exit 1`. Covered by tests that run the output
through real bash.

**Scripts match the challenge's format exactly.** Prepending `set -e` would stop a script at
the first failing command, which suits dependent tasks, but it changes the output the challenge
specifies. Commands are also never rewritten: the challenge's sample script shows
`echo "Hello World!"` for a request containing `echo 'Hello World!'`, and the output keeps the
command as sent.

**Lenient requests.** Common ways of asking for a script all work (`Accept: text/plain`,
`?format=bash`, the shell MIME types), and a JSON body is parsed even without a content type,
so plain `curl -d @job.json` works. Unsupported formats still get `406` rather than a silent
fallback.

**Validation with Ecto embedded schemas.** Ecto is used without a database, only for
`embedded_schema` + changesets. That gives type casting, all errors at once, and errors attached
to the exact task and field, rendered by the standard `traverse_errors`. Plain guards would
avoid the dependency but would need hand-written equivalents of each.

**No processes around the sort.** Each request already runs in its own process, so a crash is
isolated by Phoenix; planning is a pure function from params to `{:ok, _} | {:error, _}`.
`action_fallback` turns every error into a response in one place.

**Tests.** Besides unit and HTTP tests, the sorter is checked against a deliberately simple
O(n^2) reference implementation on 300 random jobs (acyclic and cyclic), and on 50,000-task
inputs that an accidental O(n^2) step would push past the test timeout.

