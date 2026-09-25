module SSG
  module Builder
    def self.renderer(root : String, drafts : Bool = false, base_url : String? = nil, touch : Bool = false) : Renderer
      config = Config.load(root)
      config.base_url = base_url if base_url
      site = Site.new(config, drafts: drafts)
      Renderer.new(site, TemplateEnv.build(site), touch: touch)
    end

    # One full build: load site, render everything.
    def self.build(root : String, drafts : Bool = false, clean : Bool = false, touch : Bool = false,
                   base_url : String? = nil, log : IO = STDERR) : Site
      r = renderer(root, drafts, base_url, touch)
      FileUtils.rm_rf(r.output_dir) if clean && Dir.exists?(r.output_dir)
      total = r.build
      log.puts "#{r.site.pages.size} pages, #{total} files in #{r.output_dir}: #{r.changed} written, #{r.unchanged} unchanged#{touch ? " (touched)" : ""}"
      r.site
    end

    # Files in the output directory that the site would not produce.
    # Computed from the site graph; nothing is rendered or written.
    def self.orphans(root : String, drafts : Bool = false, base_url : String? = nil) : Array(String)
      renderer(root, drafts, base_url).orphans
    end

    # One path per line, or NUL-terminated for `xargs -0`.
    def self.print_orphans(paths : Array(String), io : IO, nul : Bool = false)
      paths.each { |p| io << p << (nul ? '\0' : '\n') }
    end
  end
end
