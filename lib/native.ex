defmodule Native do
  # https://gist.github.com/rlipscombe/5f400451706efde62acbbd80700a6b7c
  @behaviour :wx_object

  @title "Canvas Example"
  @size {600, 600}

  def start_link() do
    :wx_object.start_link(__MODULE__, [], [])
  end

  def init(args \\ []) do
    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, @title, size: @size)
    :wxFrame.connect(frame, :size)
    :wxFrame.connect(frame, :close_window)

    panel = :wxPanel.new(frame, [])
    :wxPanel.connect(panel, :paint, [:callback])

    button_id = System.unique_integer([:positive, :monotonic])
    button = :wxButton.new(panel, button_id, label: 'hello')
    :wxButton.connect(button, :command_button_clicked)

    text_id = System.unique_integer([:positive, :monotonic])
    text = :wxTextCtrl.new(panel, text_id, pos: {0, 32})

    :wxFrame.show(frame)

    state = %{panel: panel, frame: frame, button: button, text: text}
    {frame, state}
  end

  def handle_event({:wx, _, _, _, {:wxSize, :size, size, _}}, state = %{panel: panel}) do
    :wxPanel.setSize(panel, size)
    {:noreply, state}
  end

  def handle_event({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    {:stop, :normal, state}
  end

  def handle_event({:wx, _, ref, _, {:wxCommand, :command_button_clicked, _, _, _}}, state) do
    # :wxButton.destroy(ref)
    text_line = :wxTextCtrl.getLineText(state.text, 0)
    :wxButton.setLabel(state.button, text_line)
    {:noreply, state}
  end

  def handle_event({:wx, _, _, _, evt}, state) do
    IO.inspect(evt, label: "Event")
    {:noreply, state}
  end

  def handle_sync_event({:wx, _, _, _, {:wxPaint, :paint}}, _, state = %{panel: panel}) do
    brush = :wxBrush.new()
    :wxBrush.setColour(brush, {255, 255, 255, 255})

    dc = :wxPaintDC.new(panel)
    :wxDC.setBackground(dc, brush)
    :wxDC.clear(dc)
    :wxPaintDC.destroy(dc)
    :ok
  end
end
