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
content type, or is sent as a form (`curl -d` without `-H 'content-type: application/json'`):

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
curl -X POST localhost:4000/jobs -H 'content-type: application/json' -d @job.json
```

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
each passed through verbatim:

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

Validation errors are keyed by field, as Phoenix's `ChangesetJSON` renders them, with one
entry per task, by position (`{}` for a valid task):

```json
{
  "errors": {
    "type": "validation",
    "detail": "validation failed",
    "tasks": [{}, { "command": ["can't be blank"], "requires": ["references unknown task \"x\""] }]
  }
}
```

Checked: `tasks` present and a list, `name` and `command` required strings, `requires` a list
of strings, unique names, known dependencies, no task requiring itself. All errors are
reported at once.

Circular dependencies report one cycle as a path where each task requires the next, and every
task that could not be scheduled (the cycle and anything waiting on it), in input order:

```json
{
  "errors": {
    "type": "cycle",
    "detail": "dependency cycle detected",
    "cycle": ["a", "b", "a"],
    "unscheduled": ["a", "b", "c"]
  }
}
```

When a script was requested, the error is a script too, so `curl ... | bash` fails loudly
instead of running anything. It prints the JSON error to stderr and exits 1:

```bash
#!/usr/bin/env bash
printf '%s\n' 'job rejected: dependency cycle detected' >&2
printf '%s\n' '{"errors":{"type":"cycle",...}}' >&2
exit 1
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

