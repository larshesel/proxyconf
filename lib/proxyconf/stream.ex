defmodule ProxyConf.Stream do
  use GenServer
  require Logger
  alias ProxyConf.ConfigCache

  def ensure_registred(grpc_stream, node_info, type_url) do
    with [] <-
           Registry.lookup(ProxyConf.StreamRegistry, {grpc_stream, node_info.cluster, type_url}),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             ProxyConf.StreamSupervisor,
             {__MODULE__, [grpc_stream, node_info, type_url]}
           ) do
      {:ok, pid}
    else
      [{pid, _value}] ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}
    end
  end

  def push_resource_changes(cluster_id, type_url, hash) do
    Registry.select(ProxyConf.StreamRegistry, [
      {{{:_, :"$1", :"$2"}, :"$3", :_}, [{:==, :"$1", cluster_id}, {:==, :"$2", type_url}],
       [:"$3"]}
    ])
    |> Enum.each(fn pid ->
      Process.send(pid, {:push_resource_changes, hash}, [])
    end)
  end

  def in_sync(cluster_id) do
    Registry.count_select(ProxyConf.StreamRegistry, [
      {{{:_, :"$1", :_}, :_, %{in_sync: :"$2"}}, [{:==, :"$1", cluster_id}, {:==, :"$2", false}],
       [true]}
    ]) == 0
  end

  def event(grpc_stream, node_info, type_url, version) do
    {:ok, pid} = ensure_registred(grpc_stream, node_info, type_url)

    GenServer.call(
      pid,
      {:event, version}
    )
  end

  def start_link([grpc_stream, node_info, type_url]) do
    GenServer.start_link(__MODULE__, [grpc_stream, node_info, type_url])
  end

  def init([grpc_stream, node_info, type_url]) do
    case Registry.register(
           ProxyConf.StreamRegistry,
           {grpc_stream, node_info.cluster, type_url},
           %{in_sync: false}
         ) do
      {:ok, _pid} ->
        link_grpc_stream_pid(grpc_stream)

        {:ok,
         %{
           stream: grpc_stream,
           type_url: type_url,
           node_info: node_info,
           version: nil,
           hash: nil,
           waiting_ack: nil
         }}

      {:error, {:already_registered, _pid} = error} ->
        {:stop, error}
    end
  end

  def handle_call({:event, version}, _from, state) do
    node_info = state.node_info

    case state.version do
      ^version ->
        # nothing to do
        Logger.debug(
          cluster: node_info.cluster,
          message: "#{state.type_url} Acked version by #{node_info.node_id} version #{version}"
        )

        update_status(%{in_sync: true})
        {:reply, :ok, %{state | waiting_ack: nil}}

      nil ->
        # new node
        {:reply, :ok, maybe_push_resources(%{state | version: 0})}
    end
  end

  def handle_info({:push_resource_changes, hash}, state) do
    if state.hash != hash do
      {:noreply, maybe_push_resources(%{state | hash: hash})}
    else
      Logger.debug(
        cluster: state.node_info.cluster,
        message: "No changes for type #{state.type_url}"
      )

      {:noreply, state}
    end
  end

  defp link_grpc_stream_pid(%GRPC.Server.Stream{payload: %{pid: pid}}) do
    # ensure we go down if grpc proc terminates
    Process.link(pid)
  end

  defp maybe_push_resources(state) do
    resources = ConfigCache.get_resources(state.node_info.cluster, state.type_url)

    new_version = state.version + 1

    {:ok, response} =
      Protobuf.JSON.from_decoded(
        %{
          "version_info" => "#{new_version}",
          "type_url" => state.type_url,
          "control_plane" => %{
            "identifier" => "#{node()}"
          },
          "resources" =>
            Enum.map(resources, fn r -> %{"@type" => state.type_url, "value" => r} end),
          "nonce" => nonce()
        },
        Envoy.Service.Discovery.V3.DiscoveryResponse
      )

    GRPC.Server.Stream.send_reply(state.stream, response, [])

    Logger.debug(
      cluster: state.node_info.cluster,
      message: "#{state.type_url} Push new version #{new_version} to #{state.node_info.node_id}"
    )

    update_status(%{in_sync: false})

    %{state | version: new_version, waiting_ack: new_version}
  end

  defp nonce do
    "#{node()}#{DateTime.utc_now() |> DateTime.to_unix(:nanosecond)}" |> Base.encode64()
  end

  defp update_status(status_map) when is_map(status_map) do
    [key] = Registry.keys(ProxyConf.StreamRegistry, self())

    Registry.update_value(ProxyConf.StreamRegistry, key, fn status ->
      Map.merge(status, status_map)
    end)
  end
end
