module IconHelper
  # Render een icon met custom classes
  # Gebruik: <%= icon :arrow_right, class: "w-5 h-5 text-blue-500" %>
  def icon(name, **options)
    css_class = options[:class] || "w-5 h-5"

    render partial: "icons/#{name}", locals: { css_class: css_class, options: options }
  end
end
