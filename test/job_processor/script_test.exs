defmodule JobProcessor.ScriptTest do
  use ExUnit.Case, async: true

  doctest JobProcessor.Script

  alias JobProcessor.{JobTask, Script}

  test "an empty job is just the shebang" do
    assert Script.render([]) == "#!/usr/bin/env bash\n"
  end

  test "commands are written exactly as given" do
    command = ~s(echo "a b" | tr ' ' '\\n' > "$HOME/out" && echo 'done')

    assert Script.render([%JobTask{name: "a", command: command}]) ==
             "#!/usr/bin/env bash\n#{command}\n"
  end
end
