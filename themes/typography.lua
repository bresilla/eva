local ui = require("morf.ui")
return function(tokens, colors, scale)
  local text
  function text(props)
    if props.morph then
      return require("themes.text_morph").make(text, props,
        { duration = tokens.duration.normal, easing = tokens.ease.standard })
    end
    props.active = nil
    props.font_family = props.font_family or tokens.auth_font or tokens.font
    props.font_size = props.font_size or scale(15)
    if props.color == nil then props.color = function() return colors.onSurface end end
    return ui.Text(props)
  end
  local function icon(name, size, color, props)
    props = props or {}
    props.text, props.font_family, props.font_size = name, tokens.icon_font, size
    props.color = color or function() return colors.onSurface end
    props.axes = props.axes or { FILL = 1 }
    return ui.Text(props)
  end
  return text, icon
end
