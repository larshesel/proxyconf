defmodule ProxyConf.Vault do
  @moduledoc """
    This module implements the Cloak.Vault used to encrypt data in Ecto.Repo
  """
  use Cloak.Vault, otp_app: :proxyconf

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!("DB_ENCRYPTION_KEY")}
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end

  defmodule EncryptedBinary do
    @moduledoc """
      Local Ecto type used in schemas that require field level encrytion
    """
    use Cloak.Ecto.Binary, vault: ProxyConf.Vault
  end
end
