require "crinja"
require "markd"

module SSG
  # Builds the Crinja environment shared by every template render in a build.
  #
  # Extra filters:   date(format), markdown, absurl, slugify, json
  # Extra functions: ref(path) -> url of the page at that content path,
  #                  highlight_css() -> stylesheet for the highlighting theme
  #
  # Shortcodes are ordinary Jinja macros in layouts/shortcodes.j2. They are
  # imported once into the environment's root context, so every template
  # and content file can call them without importing.
  module TemplateEnv
    def self.build(site : Site) : Crinja
      crinja = Crinja.new
      layout_dirs = site.config.layout_dirs.select { |d| Dir.exists?(d) }
      crinja.loader = Crinja::Loader::FileSystemLoader.new(layout_dirs) unless layout_dirs.empty?
      import_shortcodes(crinja, layout_dirs)

      crinja.filters["date"] = Crinja.filter({format: "%Y-%m-%d"}) do
        if t = target.raw.as?(Time)
          t.to_s(arguments["format"].to_s)
        else
          ""
        end
      end

      crinja.filters["markdown"] = Crinja.filter do
        Crinja::SafeString.new(Markd.to_html(target.to_s))
      end

      crinja.filters["absurl"] = Crinja.filter do
        site.absolute_url(target.to_s)
      end

      crinja.filters["slugify"] = Crinja.filter do
        Site.slugify(target.to_s)
      end

      # Crinja's tojson html-escapes its output; this one is plain JSON,
      # marked safe. Use `| json | forceescape` inside html attributes.
      crinja.filters["json"] = Crinja.filter do
        Crinja::SafeString.new(JSON.build { |b| Values.json(target, b) })
      end

      crinja.functions["ref"] = Crinja.function({path: ""}) do
        path = arguments["path"].to_s
        page = site.find(path) || raise Crinja::RuntimeError.new("ref: no page at #{path.inspect}")
        page.url
      end

      crinja.functions["highlight_css"] = Crinja.function do
        md = site.registry.processors["md"]?.as?(Processors::Markdown)
        Crinja::SafeString.new(md.try(&.css) || "")
      end

      crinja
    end

    # Macros from every shortcodes.j2 go into the root context. Theme files
    # are loaded first so that the site's definitions win.
    private def self.import_shortcodes(crinja : Crinja, layout_dirs : Array(String))
      layout_dirs.reverse_each do |dir|
        path = File.join(dir, "shortcodes.j2")
        next unless File.exists?(path)
        begin
          # Rendering in the root context defines the macros there.
          crinja.from_string(File.read(path)).render(IO::Memory.new, crinja)
        rescue e : Crinja::Error
          raise Error.new("in #{path}: #{e.message}", cause: e)
        end
      end
    end
  end
end
