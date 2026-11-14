defmodule Defdo.Uploader.ConnectionCheckTest do
  use ExUnit.Case, async: true

  alias Defdo.Uploader.ConnectionCheck

  @stub __MODULE__

  # An object store small enough to read: PUT stores, GET/HEAD read, DELETE
  # removes. `opts` break one behaviour at a time.
  defp store(opts \\ []) do
    {:ok, agent} = Agent.start_link(fn -> %{objects: %{}, log: []} end)

    Req.Test.stub(@stub, fn conn ->
      key = conn.request_path
      Agent.update(agent, &%{&1 | log: [{conn.method, key} | &1.log]})
      objects = Agent.get(agent, & &1.objects)

      cond do
        status = opts[:all] ->
          Plug.Conn.send_resp(conn, status, "")

        conn.method == "PUT" and opts[:put] ->
          Plug.Conn.send_resp(conn, opts[:put], "")

        conn.method == "PUT" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          stored = if opts[:corrupt], do: "something else", else: body
          Agent.update(agent, &put_in(&1.objects[key], stored))
          Plug.Conn.send_resp(conn, 200, "")

        conn.method == "DELETE" and opts[:delete] ->
          Plug.Conn.send_resp(conn, opts[:delete], "")

        conn.method == "DELETE" and opts[:keep] ->
          Plug.Conn.send_resp(conn, 204, "")

        conn.method == "DELETE" ->
          Agent.update(agent, &%{&1 | objects: Map.delete(&1.objects, key)})
          Plug.Conn.send_resp(conn, 204, "")

        is_map_key(objects, key) ->
          Plug.Conn.send_resp(conn, 200, if(conn.method == "HEAD", do: "", else: objects[key]))

        true ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    agent
  end

  defp config(bucket \\ "assets") do
    %{
      access_key_id: "AKIATEST",
      secret_access_key: "TOPSECRETVALUE",
      bucket: bucket,
      region: "auto",
      endpoint: "https://s3.test",
      req_options: [plug: {Req.Test, @stub}]
    }
  end

  defp statuses(result), do: Enum.map(result.steps, &{&1.step, &1.status})
  defp objects(agent), do: Agent.get(agent, & &1.objects)
  defp log(agent), do: agent |> Agent.get(& &1.log) |> Enum.reverse()

  test "connects, writes, edits and deletes one object, and leaves nothing behind" do
    agent = store()
    result = ConnectionCheck.run(config())

    assert result.ok?
    assert statuses(result) == [connect: :ok, write: :ok, edit: :ok, delete: :ok]
    assert result.leftover == nil
    assert objects(agent) == %{}

    methods = Enum.map(log(agent), &elem(&1, 0))
    assert methods == ~w(HEAD PUT GET PUT GET DELETE HEAD)

    # one object, a random name under the check folder, nothing else touched
    assert [key] = log(agent) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert key =~ ~r|^/assets/\.defdo-connection-check/[0-9a-f]{16}\.txt$|
  end

  test "the probe stays inside the bucket's prefix" do
    agent = store()
    assert ConnectionCheck.run(config("assets/tenants/t1")).ok?

    assert [{_, key} | _] = log(agent)
    assert key =~ ~r|^/assets/tenants/t1/\.defdo-connection-check/|
  end

  test "rejected credentials fail at connect and nothing is written" do
    agent = store(all: 403)
    result = ConnectionCheck.run(config())

    refute result.ok?

    assert statuses(result) == [
             connect: :error,
             write: :skipped,
             edit: :skipped,
             delete: :skipped
           ]

    assert hd(result.steps).reason == {:http_status, 403}
    assert Enum.map(log(agent), &elem(&1, 0)) == ["HEAD"]
  end

  test "a read-only key connects but fails at write" do
    store(put: 403)
    result = ConnectionCheck.run(config())

    assert statuses(result) == [connect: :ok, write: :error, edit: :skipped, delete: :skipped]
    assert Enum.at(result.steps, 1).reason == {:http_status, 403}
    assert result.leftover == nil
  end

  test "bytes that do not come back as written fail the write, and the object is removed" do
    agent = store(corrupt: true)
    result = ConnectionCheck.run(config())

    assert statuses(result) == [connect: :ok, write: :error, edit: :skipped, delete: :skipped]
    assert Enum.at(result.steps, 1).reason == :content_mismatch
    assert result.leftover == nil
    assert objects(agent) == %{}
  end

  test "a key that may not delete fails the last step and reports the leftover" do
    agent = store(delete: 403)
    result = ConnectionCheck.run(config())

    assert statuses(result) == [connect: :ok, write: :ok, edit: :ok, delete: :error]
    assert result.leftover =~ ".defdo-connection-check/"
    assert map_size(objects(agent)) == 1
  end

  test "a delete the store accepts but does not perform is caught" do
    store(keep: true)
    result = ConnectionCheck.run(config())

    assert List.last(result.steps) == %{step: :delete, status: :error, reason: :still_there}
  end

  test "incomplete credentials never reach the network" do
    Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)
    result = ConnectionCheck.run(%{config() | secret_access_key: ""})

    assert hd(result.steps) == %{step: :connect, status: :error, reason: :missing_credentials}
  end

  test "no result carries the secret" do
    store(all: 500)
    refute inspect(ConnectionCheck.run(config())) =~ "TOPSECRETVALUE"
  end
end
