defmodule Defdo.Uploader.KeyTest do
  use ExUnit.Case, async: true

  alias Defdo.Tenant.Context
  alias Defdo.Uploader.{Key, Kind}

  setup do
    on_exit(fn -> Context.clear() end)
    {:ok, logo} = Kind.fetch(:tenant_logo)
    {:ok, picture} = Kind.fetch(:user_picture)
    {:ok, logo: logo, picture: picture}
  end

  test "tenant-owned layout", %{logo: logo} do
    assert Key.base(logo, tenant_id: "t1", id: "brand", version: "v1") ==
             {:ok, "tenants/t1/tenant_logo/brand/v1"}
  end

  test "user-owned layout nests under the user", %{picture: picture} do
    assert Key.base(picture, tenant_id: "t1", id: "u-42", version: "v1") ==
             {:ok, "tenants/t1/users/u-42/user_picture/v1"}
  end

  test "reads the tenant from process context", %{picture: picture} do
    Context.put(Context.new("ctx-tenant"))

    assert {:ok, "tenants/ctx-tenant/users/u/user_picture/v1"} =
             Key.base(picture, id: "u", version: "v1")
  end

  test "an explicit tenant that disagrees with the context is an error", %{picture: picture} do
    Context.put(Context.new("ctx-tenant"))

    assert Key.base(picture, tenant_id: "other", id: "u", version: "v1") ==
             {:error, :tenant_mismatch}
  end

  test "no tenant at all is an error, never a shared default", %{picture: picture} do
    assert Key.base(picture, id: "u", version: "v1") == {:error, :tenant_required}
  end

  test "rejects segments that could traverse or add separators", %{picture: picture} do
    for bad <- ["../other", "a/b", ".hidden", "a..b", "", "sp ace", String.duplicate("a", 129)] do
      assert {:error, _} = Key.base(picture, tenant_id: "t1", id: bad, version: "v1"),
             "expected #{inspect(bad)} to be rejected"
    end

    assert Key.base(picture, tenant_id: "../t", id: "u", version: "v1") ==
             {:error, {:invalid_segment, :tenant_id}}
  end

  test "requires an id", %{picture: picture} do
    assert Key.base(picture, tenant_id: "t1") == {:error, {:missing, :id}}
  end

  test "validates and applies a key prefix", %{logo: logo} do
    assert Key.base(logo, tenant_id: "t1", id: "b", version: "v1", key_prefix: "/prod/eu/") ==
             {:ok, "prod/eu/tenants/t1/tenant_logo/b/v1"}

    assert Key.base(logo, tenant_id: "t1", id: "b", version: "v1", key_prefix: "prod/../x") ==
             {:error, {:invalid_segment, :key_prefix}}
  end

  test "generated versions are valid segments and unique" do
    versions = for _ <- 1..200, do: Key.new_version()
    assert Enum.uniq(versions) == versions
    assert Enum.all?(versions, &(&1 =~ ~r/\A\d+-[0-9a-f]{8}\z/))
  end

  test "variant keys use real extensions" do
    assert Key.variant("b", "fallback", :jpeg) == "b/fallback.jpg"
    assert Key.variant("b", "display", :webp) == "b/display.webp"
  end
end
