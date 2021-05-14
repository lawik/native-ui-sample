defmodule Native.Server do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, [])
  end

  @impl GenServer
  def init(_) do
    {:wx_ref, _, _, pid} = Native.start_link()
    ref = Process.monitor(pid)

    {:ok, {ref, pid}}
  end

  def handle_info({:DOWN, _, _, _, _}, state) do
    System.stop(0)
    {:stop, :ignore, nil}
  end
end
