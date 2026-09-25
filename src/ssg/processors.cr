require "markd"
require "crinja"
require "html"
require "sass"

module SSG
  module Processors
    class Markdown < Chain::Processor
      getter formatter : Tartrazine::Html?

      def initialize(@options = Markd::Options.new, @formatter : Tartrazine::Html? = nil)
      end

      def self.formatter(theme : String?, line_numbers : Bool) : Tartrazine::Html?
        return nil unless theme
        Tartrazine::Html.new(theme: Tartrazine.theme(theme), line_numbers: line_numbers, class_prefix: "hl-")
      rescue e : Exception
        raise Error.new("config: unknown highlight theme #{theme.inspect}", cause: e)
      end

      # Stylesheet for the highlighting theme, for templates to emit.
      def css : String
        @formatter.try(&.style_defs) || ""
      end

      def ext : String
        "md"
      end

      def produces : String?
        "html"
      end

      def call(input : Bytes, ctx : Chain::Context) : Bytes
        call_text(input, ctx) { |s| add_heading_ids(Markd.to_html(s, @options, formatter: @formatter)) }
      end

      # Give headings an id (as Hugo does) so that they can be linked and
      # listed in a table of contents. Ids are made unique within the page.
      private def add_heading_ids(html : String) : String
        seen = {} of String => Int32
        html.gsub(/<h([1-6])>(.*?)<\/h\1>/m) do
          level, inner = $1, $2
          base = Site.slugify(HTML.unescape(inner.gsub(/<[^>]*>/, "")))
          base = "heading" if base.empty?
          n = (seen[base] = (seen[base]? || 0) + 1)
          id = n == 1 ? base : "#{base}-#{n}"
          %(<h#{level} id="#{id}">#{inner}</h#{level}>)
        end
      end
    end

    # Transparent: the output format is whatever the filename says next.
    class Jinja < Chain::Processor
      def ext : String
        "j2"
      end

      def call(input : Bytes, ctx : Chain::Context) : Bytes
        call_text(input, ctx) do |source|
          bindings = {} of String => Crinja::Value
          bindings["site"] = Crinja::Value.new(ctx.site)
          if page = ctx.page
            bindings["page"] = Crinja::Value.new(page)
          end
          ctx.vars.each { |k, v| bindings[k] = v }
          ctx.env.from_string(source).render(bindings)
        end
      rescue e : Crinja::Error
        raise Error.new("in #{ctx.origin}: #{e.message}", cause: e)
      end
    end

    # Sass/SCSS via libsass. `style.css.scss` and `style.scss` both produce
    # `style.css`; `.sass` is the indented syntax. `@import` looks next to
    # the source file first, then in every static directory (site, then
    # themes), so a site can override a theme's partial.
    class Sass < Chain::Processor
      def initialize(@ext : String = "scss", @style : ::Sass::OutputStyle = ::Sass::OutputStyle::NESTED)
      end

      def ext : String
        @ext
      end

      def produces : String?
        "css"
      end

      def self.style(name : String) : ::Sass::OutputStyle
        ::Sass::OutputStyle.parse(name)
      rescue ArgumentError
        raise Error.new("config: unknown sass style #{name.inspect} (nested, expanded, compact, compressed)")
      end

      def call(input : Bytes, ctx : Chain::Context) : Bytes
        call_text(input, ctx) do |source|
          ::Sass.compile(source, include_path: include_paths(ctx).join(':'), output_style: @style,
            is_indented_syntax_src: @ext == "sass", input_path: ctx.origin)
        end
      rescue e : ::Sass::CompilerError
        raise Error.new("in #{ctx.origin}: #{e.message}", cause: e)
      end

      # The importing file's directory, then the same relative directory in
      # every static directory (site first, then themes), then the static
      # roots. So `css/main.scss` importing "vars" finds the site's
      # `css/_vars.scss` before a theme's.
      private def include_paths(ctx : Chain::Context) : Array(String)
        statics = ctx.site.config.static_dirs
        origin_dir = File.dirname(ctx.origin)
        paths = [origin_dir]
        if base = statics.find { |d| ctx.origin.starts_with?(d + "/") }
          rel = File.dirname(ctx.origin[(base.size + 1)..])
          statics.each { |d| paths << File.join(d, rel) } unless rel == "."
        end
        paths.concat(statics)
        paths.uniq.select { |d| Dir.exists?(d) }
      end
    end

    # A deliberately simple html -> txt converter. It exists to make the
    # converter mechanism real and testable; a pdf converter would be
    # registered the same way.
    class HtmlToText < Chain::Converter
      def from : String
        "html"
      end

      def to : String
        "txt"
      end

      def call(input : Bytes, ctx : Chain::Context) : Bytes
        call_text(input, ctx) do |html|
          text = html.gsub(/<\s*(br|\/p|\/h[1-6]|\/li|\/div|\/tr)\s*>/i, "\n")
          text = text.gsub(/<[^>]*>/, "")
          HTML.unescape(text).gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip + "\n"
        end
      end
    end

    def self.default_registry(config : Config) : Chain::Registry
      default_registry(config.markdown, Markdown.formatter(config.highlight_theme, config.line_numbers?), Sass.style(config.sass_style))
    end

    def self.default_registry(markdown = Markd::Options.new, formatter : Tartrazine::Html? = nil,
                              sass_style = ::Sass::OutputStyle::NESTED) : Chain::Registry
      Chain::Registry.new
        .register(Markdown.new(markdown, formatter))
        .register(Sass.new("scss", sass_style))
        .register(Sass.new("sass", sass_style))
        .register(Jinja.new)
        .register(HtmlToText.new)
    end
  end
end
