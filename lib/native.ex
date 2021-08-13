defmodule Native do
  # https://gist.github.com/rlipscombe/5f400451706efde62acbbd80700a6b7c
  @behaviour :wx_object

  @title "Canvas Example"
  @size {600, 600}

  @editors 3

  import Bitwise

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

    editors = Enum.map(1..@editors, fn num ->
      editor_id = System.unique_integer([:positive, :monotonic])
      editor_ref = :wxStyledTextCtrl.new(panel, id: editor_id, pos: {0, 128*num})
      :wxStyledTextCtrl.setModEventMask(editor_ref, 0x13)
      :wxEvtHandler.connect(editor_ref, :stc_modified, id: editor_id)
      editor_ref
    end)


    :wxFrame.show(frame)

    state = %{panel: panel, frame: frame, button: button, editors: editors, document: TextDelta.new(), last_events: %{}}
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
    IO.inspect(flags, base: :hex)
    IO.inspect(flags, base: :binary)
    op = if (flags &&& 0x10) != 0 do
      if (flags &&& 0x1) != 0 do
        IO.inspect({:insert, ref, text, length, pos})
        send(self(), {:insert, ref, text, length, pos})

      end
      if (flags &&& 0x2) != 0 do
        IO.inspect({:delete, ref, text, length, pos})
        send(self(), {:delete, ref, text, length, pos})
      end
    end

    {:noreply, state}

#      change = if pos > 0 do
#        TextDelta.retain(TextDelta.new(), pos)
#      else
#        TextDelta.new()
#      end
#
#      change = case op do
#        :insert ->
#          TextDelta.insert(change, text)
#        :delete ->
#          TextDelta.delete(change, length)
#        :nothing ->
#          change
#      end
#      IO.inspect(ref, label: "current")
#
#      if change.ops != [] do
#        {:ok, document} = state.document
#        |> IO.inspect(label: "doc before")
#        |> TextDelta.apply(change)
#
#        document
#        |> IO.inspect(label: "doc after")
#
#        if state.document != document do
#          new_text = document.ops
#                     |> Enum.map(fn %{insert: chars} ->
#                       chars
#                     end)
#                     |> Enum.reverse()
#                     |> Enum.join()
#                     |> IO.inspect(label: "text")
#
#          :wxStyledTextCtrl.setText(other_editor, new_text)
#          :wxStyledTextCtrl.gotoPos(other_editor, other_last_pos)
#          {:noreply, %{state | document: document, last_text: new_text, last_editor: ref}}
#        else
#          IO.puts("no change in doc")
#          {:noreply, state}
#        end
#      else
#        IO.puts("no ops")
#        {:noreply, state}
#      end
#
#    end
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

  def handle_info({:insert, ref, text, length, pos} = event, state) do
    last_event = state.last_events[ref]
    case last_event do
      {:insert, last_ref, ^text, ^length, ^pos} when ref != last_ref ->
        last_events = Map.delete(state.last_events, ref)
        {:noreply, %{state | last_events: last_events}}

      _ ->
        last_events = on_other_editors(ref, state.editors, fn editor, last_events ->
          :wxStyledTextCtrl.insertText(editor, pos, text)
          Map.put(last_events, editor, event)
        end)
        {:noreply, %{state | last_events: last_events}}
    end
  end

  def handle_info({:delete, ref, text, length, pos} = event, state) do
    last_event = state.last_events[ref]
    case last_event do
      {:delete, last_ref, _, _, _} when ref != last_ref ->
        last_events = Map.delete(state.last_events, ref)
        {:noreply, %{state | last_events: last_events}}

      _ ->
        last_events = on_other_editors(ref, state.editors, fn editor, last_events ->
          position = :wxStyledTextCtrl.getCurrentPos(editor)
          :wxStyledTextCtrl.setCurrentPos(editor, pos)
          :wxStyledTextCtrl.deleteBack(editor)
          :wxStyledTextCtrl.setCurrentPos(editor, position)
          Map.put(last_events, editor, event)
        end)
        {:noreply, %{state | last_events: last_events}}
    end
  end

  defp on_other_editors(ref, editors, callback) do
    editors
    |> Enum.filter(fn other_ref ->
      ref != other_ref
    end)
    |> Enum.reduce(%{}, callback)
  end

  def as_binary(num) do
    List.to_string(:io_lib.format("~8.2B", [num]))
  end
end
