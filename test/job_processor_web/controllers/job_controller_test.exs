defmodule JobProcessorWeb.JobControllerTest do
  use JobProcessorWeb.ConnCase, async: true

  @job %{
    "tasks" => [
      %{"name" => "task-1", "command" => "touch /tmp/file1"},
      %{"name" => "task-2", "command" => "cat /tmp/file1", "requires" => ["task-3"]},
      %{
        "name" => "task-3",
        "command" => "echo 'Hello World!' > /tmp/file1",
        "requires" => ["task-1"]
      },
      %{"name" => "task-4", "command" => "rm /tmp/file1", "requires" => ["task-2", "task-3"]}
    ]
  }

  describe "POST /jobs" do
    test "returns tasks in execution order", %{conn: conn} do
      conn = post(conn, ~p"/jobs", @job)

      assert json_response(conn, 200) == %{
               "tasks" => [
                 %{"name" => "task-1", "command" => "touch /tmp/file1"},
                 %{"name" => "task-3", "command" => "echo 'Hello World!' > /tmp/file1"},
                 %{"name" => "task-2", "command" => "cat /tmp/file1"},
                 %{"name" => "task-4", "command" => "rm /tmp/file1"}
               ]
             }
    end

    test "returns validation errors per task", %{conn: conn} do
      job = %{"tasks" => [%{"name" => "a", "requires" => ["missing"]}]}
      conn = post(conn, ~p"/jobs", job)

      assert json_response(conn, 422) == %{
               "errors" => %{
                 "type" => "validation",
                 "detail" => "validation failed",
                 "tasks" => [
                   %{
                     "command" => ["can't be blank"],
                     "requires" => [~s(references unknown task "missing")]
                   }
                 ]
               }
             }
    end

    test "rejects a body without tasks", %{conn: conn} do
      conn = post(conn, ~p"/jobs", %{})

      assert json_response(conn, 422) == %{
               "errors" => %{
                 "type" => "validation",
                 "detail" => "validation failed",
                 "tasks" => ["can't be blank"]
               }
             }
    end

    test "reports a cycle", %{conn: conn} do
      job = %{
        "tasks" => [
          %{"name" => "a", "command" => "echo a", "requires" => ["b"]},
          %{"name" => "b", "command" => "echo b", "requires" => ["a"]},
          %{"name" => "c", "command" => "echo c", "requires" => ["a"]}
        ]
      }

      conn = post(conn, ~p"/jobs", job)

      assert json_response(conn, 422) == %{
               "errors" => %{
                 "type" => "cycle",
                 "detail" => "dependency cycle detected",
                 "cycle" => ["a", "b", "a"],
                 "unscheduled" => ["a", "b", "c"]
               }
             }
    end
  end

  describe "POST /jobs content negotiation" do
    @script """
    #!/usr/bin/env bash
    touch /tmp/file1
    echo 'Hello World!' > /tmp/file1
    cat /tmp/file1
    rm /tmp/file1
    """

    test "defaults to JSON for Accept: */*", %{conn: conn} do
      conn = conn |> put_req_header("accept", "*/*") |> post(~p"/jobs", @job)

      assert %{"tasks" => [_, _, _, _]} = json_response(conn, 200)
    end

    test "returns a bash script for Accept: text/x-shellscript", %{conn: conn} do
      conn = conn |> put_req_header("accept", "text/x-shellscript") |> post(~p"/jobs", @job)

      assert response(conn, 200) == @script
      assert response_content_type(conn, :sh) =~ "text/x-shellscript"
    end

    test "returns a bash script for Accept: application/x-sh", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/x-sh") |> post(~p"/jobs", @job)

      assert response(conn, 200) == @script
    end

    test "returns a bash script for ?_format=sh", %{conn: conn} do
      conn = post(conn, ~p"/jobs?_format=sh", @job)

      assert response(conn, 200) == @script
    end

    test "returns a failing script for errors when a script was requested", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/x-shellscript")
        |> post(~p"/jobs", %{"tasks" => [%{"name" => "a"}]})

      assert response(conn, 422) =~ "job rejected: validation failed"
      assert response_content_type(conn, :sh) =~ "text/x-shellscript"
    end

    for accept <- ["text/x-sh", "application/x-shellscript"] do
      @accept accept
      test "returns a bash script for Accept: #{accept}", %{conn: conn} do
        conn = conn |> put_req_header("accept", @accept) |> post(~p"/jobs", @job)

        assert response(conn, 200) == @script
        assert response_content_type(conn, :sh) =~ "text/x-shellscript"
      end
    end

    test "returns a bash script as text/plain for Accept: text/plain", %{conn: conn} do
      conn = conn |> put_req_header("accept", "text/plain") |> post(~p"/jobs", @job)

      assert response(conn, 200) == @script
      assert response_content_type(conn, :txt) =~ "text/plain"
    end

    test "returns errors as a failing script for Accept: text/plain", %{conn: conn} do
      conn = conn |> put_req_header("accept", "text/plain") |> post(~p"/jobs", %{})

      assert response(conn, 422) =~ "job rejected: validation failed"
      assert response_content_type(conn, :txt) =~ "text/plain"
    end

    for format <- ["sh", "bash"] do
      @format format
      test "returns a bash script for ?format=#{format}", %{conn: conn} do
        conn = post(conn, "/jobs?format=#{@format}", @job)

        assert response(conn, 200) == @script
      end
    end

    test "?format=json overrides an Accept header asking for a script", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/x-shellscript")
        |> post(~p"/jobs?format=json", @job)

      assert %{"tasks" => [_, _, _, _]} = json_response(conn, 200)
    end

    test "rejects an unknown ?format= instead of falling back to JSON", %{conn: conn} do
      assert_error_sent 406, fn -> post(conn, ~p"/jobs?format=xml", @job) end
    end

    test "rejects formats it cannot produce", %{conn: conn} do
      assert_error_sent 406, fn ->
        conn |> put_req_header("accept", "text/html") |> post(~p"/jobs", @job)
      end
    end
  end

  describe "request bodies" do
    @body Jason.encode!(@job)

    test "parses JSON sent without a content type" do
      # Phoenix.ConnTest refuses a raw body without a content type, so build the request
      # with Plug.Test and send it through the endpoint like a real one.
      conn = Plug.Test.conn(:post, "/jobs", @body) |> @endpoint.call(@endpoint.init([]))

      assert %{"tasks" => [%{"name" => "task-1"} | _]} = json_response(conn, 200)
    end

    test "parses JSON sent as a form (curl -d without -H)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(~p"/jobs", @body)

      assert %{"tasks" => [%{"name" => "task-1"} | _]} = json_response(conn, 200)
    end

    test "rejects malformed JSON with 400", %{conn: conn} do
      assert_error_sent 400, fn ->
        conn |> put_req_header("content-type", "application/json") |> post(~p"/jobs", "{not json")
      end
    end
  end

  describe "POST /jobs/script" do
    test "matches the spec's expected script, line for line", %{conn: conn} do
      # The spec's script writes `echo "Hello World!"` although its request has
      # `echo 'Hello World!'`; commands are passed through verbatim, so that is the one
      # line we expect to differ.
      spec_script = """
      #!/usr/bin/env bash
      touch /tmp/file1
      echo "Hello World!" > /tmp/file1
      cat /tmp/file1
      rm /tmp/file1
      """

      script = conn |> post(~p"/jobs/script", @job) |> response(200)

      assert String.replace(script, "'Hello World!'", ~s("Hello World!")) == spec_script
    end

    test "returns a bash script as text/plain for Accept: text/plain", %{conn: conn} do
      conn = conn |> put_req_header("accept", "text/plain") |> post(~p"/jobs/script", @job)

      assert response(conn, 200) == @script
      assert response_content_type(conn, :txt) =~ "text/plain"
    end

    test "returns a bash script in execution order", %{conn: conn} do
      conn = post(conn, ~p"/jobs/script", @job)

      assert response(conn, 200) == """
             #!/usr/bin/env bash
             touch /tmp/file1
             echo 'Hello World!' > /tmp/file1
             cat /tmp/file1
             rm /tmp/file1
             """

      assert response_content_type(conn, :sh) =~ "text/x-shellscript"
    end

    @tag :tmp_dir
    test "a validation error is a script that runs nothing and exits 1", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      marker = Path.join(tmp_dir, "injected")
      task = %{"name" => "a", "command" => "echo a", "requires" => ["$(touch #{marker})"]}
      conn = post(conn, ~p"/jobs/script", %{"tasks" => [task]})

      script = response(conn, 422)
      assert response_content_type(conn, :sh) =~ "text/x-shellscript"

      {output, status} = System.cmd("bash", ["-c", script], stderr_to_stdout: true)

      assert status == 1
      assert output =~ "job rejected: validation failed"
      # The hostile name is printed back literally (JSON-escaped), not executed.
      assert output =~ "references unknown task \\\"$(touch #{marker})\\\""
      refute File.exists?(marker)
    end

    test "a cycle is a script that exits 1", %{conn: conn} do
      tasks = [
        %{"name" => "a", "command" => "echo a", "requires" => ["b"]},
        %{"name" => "b", "command" => "echo b", "requires" => ["a"]}
      ]

      conn = post(conn, ~p"/jobs/script", %{"tasks" => tasks})

      {output, 1} = System.cmd("bash", ["-c", response(conn, 422)], stderr_to_stdout: true)
      assert output =~ "job rejected: dependency cycle detected"
    end
  end
end
