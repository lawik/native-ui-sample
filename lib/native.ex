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

    editor_a_id = System.unique_integer([:positive, :monotonic])
    editor_a = :wxStyledTextCtrl.new(panel, id: editor_a_id, pos: {0, 72})
    :wxEvtHandler.connect(editor_a, :stc_modified, id: editor_a_id)

    editor_b_id = System.unique_integer([:positive, :monotonic])
    editor_b = :wxStyledTextCtrl.new(panel, id: editor_b_id, pos: {128, 72})
    :wxEvtHandler.connect(editor_b, :stc_modified, id: editor_b_id)
    #:wxEvtHandler.connect(editor, :stc_change, id: editor_id)
    #:wxEvtHandler.connect(editor, :stc_charadded, id: editor_id)

    :wxFrame.show(frame)

    state = %{panel: panel, frame: frame, button: button, text: text, editor_a: editor_a, editor_b: editor_b, delta_a: TextDelta.new(), delta_b: TextDelta.new(), document: TextDelta.new(), last_text: nil, last_editor: nil}
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
    #text = :wxStyledTextCtrl.getText(state.editor)
    {:noreply, state}
  end

  def handle_event({:wx, _, ref, _, {:wxStyledText, :stc_modified, pos, _, _, flags, text, length, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}, %{document: document} = state) do
    if state.last_text == text and state.last_editor != ref do
      {:noreply, state}
    else
      last_pos = :wxStyledTextCtrl.getCurrentPos(ref)
      {current_delta, other_delta, other_editor} = if ref == state.editor_a do
        {state.delta_a, state.delta_b, state.editor_b}
      else
        {state.delta_b, state.delta_a, state.editor_a}
      end

      other_last_pos = :wxStyledTextCtrl.getCurrentPos(other_editor)

      op = case <<flags>> do
        # Insert, 0x01
        <<_::7, 1::1>> <> _ ->
          IO.inspect({:insert, text, length, pos})
          :insert

        # Delete, 0x02
        <<_::6, 1::1, 0::1>> <> _ ->
          IO.inspect({:delete, text, length, pos})
          :delete

        _bin_flags ->
          # <<i1::1, i2::1, i3::1, i4::1, i5::1, i6::1, i7::1, i8::1>> = bin_flags
          # IO.inspect({i1, i2, i3, i4, i5, i6, i7, i8})
          # IO.inspect(byte_size(bin_flags))
          # IO.inspect(bin_flags)
          # IO.inspect({flags, as_binary(flags)})
          :nothing
      end

      change = if pos > 0 do
        TextDelta.retain(TextDelta.new(), pos)
      else
        TextDelta.new()
      end

      change = case op do
        :insert ->
          TextDelta.insert(change, text)
        :delete ->
          TextDelta.delete(change, length)
        :nothing ->
          change
      end

      {:ok, document} = state.document
      |> IO.inspect(label: "doc before")
      |> TextDelta.apply(change)
      |> IO.inspect(label: "doc after")

      new_text = document.ops
                 |> Enum.map(fn %{insert: chars} ->
                   chars
                 end)
                 |> Enum.reverse()
                 |> Enum.join()
                 |> IO.inspect()

      :wxStyledTextCtrl.setText(other_editor, new_text)
      :wxStyledTextCtrl.gotoPos(other_editor, other_last_pos)

      {:noreply, %{state | document: document, last_text: new_text, last_editor: ref}}
    end
  end

  # # Insert text
  # def handle_event({:wx, _, ref, _, {:wxStyledText, :stc_modified, pos, _, _, <<_::1,1::1,_::6>> <> _flags, text, length, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}, state) do
  #   IO.inspect({"insert", pos, length, text})
  #   {:noreply, state}
  # end

  # # Delete text
  # def handle_event({:wx, _, ref, _, {:wxStyledText, :stc_modified, pos, _, _, <<_::1,_::1,1::1,_::5>> <> _flags, text, length, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}, state) do
  #   IO.inspect({"delete", pos, length, text})
  #   {:noreply, state}
  # end

  def handle_event({:wx, _, _, _, evt}, state) do
    IO.inspect({evt, System.unique_integer([:positive, :monotonic])}, label: "Event")
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

  def as_binary(num) do
    List.to_string(:io_lib.format("~8.2B", [num]))
  end
end
