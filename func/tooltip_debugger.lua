function tooltip_debugger(t)
    imgui.begin_tooltip()
    imgui.text(tostring(t))
    imgui.end_tooltip()
end

return tooltip_debugger