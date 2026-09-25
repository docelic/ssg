require "file_utils"
require "html"

module SSG
  # Renders pages and resources into the output directory.
  #
  # Layout lookup for a page of kind K (page or list), format F and top-level
  # section S tries, in order, the names: `layout` from front matter if set,
  # `home` for the home page, then K; each first under `layouts/S/` and then
  # under `layouts/`. A layout matches when its resolved base name equals
  # the candidate and its resolved format equals F. So `layouts/page.html.j2`
  # serves html, `layouts/list.xml.j2` serves xml, and `layouts/tags/list.html.j2`
  # serves both /tags/ and /tags/foo/.
  class Renderer
    getter site : Site
    getter env : Crinja
    getter output_dir : String

    # {subdir, base, format} => absolute path of the layout file
    @layouts = {} of {String, String, String} => String
    @layout_formats = Set(String).new
    @registry : Chain::Registry
    getter changed = 0
    getter unchanged = 0

    # With *touch*, files whose content is unchanged still get a fresh
    # mtime, so that after a build every current output file is newer than
    # the build's start and stale files can be found by age.
    def initialize(@site, @env, @output_dir = site.config.output_dir, @touch = false)
      @registry = site.registry
      index_layouts
    end

    # One output file: where it goes, where it came from, and how to make
    # its bytes. Producing is deferred so that a plan can be computed
    # without rendering anything.
    record Job, rel : String, origin : String, produce : -> Bytes

    # Every output file this site produces, computed from the site graph
    # alone. Collisions between outputs are detected here.
    def plan : Array(Job)
      jobs = [] of Job
      @site.pages.each { |p| plan_page(p, jobs) }
      @site.pages.each { |p| plan_aliases(p, jobs) }
      @site.pages.each { |p| p.resources.each { |r| plan_resource(r, jobs) } }
      plan_static(jobs)
      seen = {} of String => String
      jobs.each do |j|
        if prev = seen[j.rel]?
          raise Error.new("output collision at #{j.rel}: #{prev} and #{j.origin}")
        end
        seen[j.rel] = j.origin
      end
      jobs
    end

    def build
      @changed = @unchanged = 0
      jobs = plan
      Dir.mkdir_p(@output_dir)
      # Process every page body before rendering any layout, so that a
      # layout can use the content of other pages (a feed for a section).
      @site.pages.each { |p| process_variants(p) }
      jobs.each { |j| write(j.rel, j.produce.call) }
      jobs.size
    end

    # Files under the output directory that the plan does not produce.
    # Absolute paths, sorted. Needs no build.
    def orphans : Array(String)
      planned = plan.map(&.rel).to_set
      return [] of String unless Dir.exists?(@output_dir)
      Dir.glob(File.join(@output_dir, "**", "*"), match: File::MatchOptions::DotFiles)
        .select { |p| File.file?(p) }
        .reject { |p| planned.includes?(p[(@output_dir.size + 1)..]) }
        .sort!
    end

    # ---- layouts ---------------------------------------------------------

    # The site's layouts first, then each theme's; the first file found for
    # a {dir, name, format} wins.
    private def index_layouts
      @site.config.layout_dirs.each do |dir|
        next unless Dir.exists?(dir)
        Dir.glob(File.join(dir, "**", "*")).each do |path|
          next unless File.file?(path)
          name = File.basename(path)
          next if name.starts_with?('.')
          resolved = @registry.resolve(name)
          format = resolved.format || next
          rel_dir = File.dirname(path[(dir.size + 1)..])
          rel_dir = "" if rel_dir == "."
          key = {rel_dir, resolved.base, format}
          next if @layouts.has_key?(key)
          @layouts[key] = path
          @layout_formats << format
        end
      end
    end

    private def layout_candidates(page : Page) : Array({String, String})
      names = [] of String
      if l = page.layout
        names << l
      end
      names << "home" if page.home?
      names << page.kind.to_s
      dirs = page.section.empty? ? [""] : [page.section, ""]
      names.flat_map { |n| dirs.map { |d| {d, n} } }
    end

    def find_layout(page : Page, format : String) : String?
      layout_candidates(page).each do |dir, base|
        if path = @layouts[{dir, base, format}]?
          return path
        end
      end
      nil
    end

    # ---- pages -----------------------------------------------------------

    private def process_variants(page : Page)
      page.content.clear
      page.variants.each do |v|
        ctx = Chain::Context.new(@site, @env, page, origin: v.source_path)
        page.content[v.format] = @registry.process(v.body, v.resolved, ctx)
      end
    end

    # A page is rendered in every format one of its variants provides, plus
    # every format for which a layout matches its kind, narrowed by
    # `outputs` from front matter. Html list pages with `paginate` set are
    # rendered once per slice of their pages.
    private def plan_page(page : Page, jobs : Array(Job))
      formats = Set(String).new
      page.variants.each { |v| formats << v.format }
      @layout_formats.each { |f| formats << f if find_layout(page, f) }
      formats = Set{File.extname(page.url).lchop('.')} if page.file_url?
      if allowed = page.outputs
        formats = formats.select { |f| allowed.includes?(f) }.to_set
      end
      origin = page.variants.first?.try(&.source_path) || page.to_s
      has_variant = page.variants.map(&.format).to_set

      formats.each do |format|
        rel = page.output_path(format)
        layout = find_layout(page, format)
        unless layout
          jobs << body_job(rel, origin, page, format) if has_variant.includes?(format)
          next
        end

        per = page.paginate
        if format == "html" && per > 0 && page.pages.size > per
          slices = page.pages.each_slice(per).to_a
          slices.each_with_index do |slice, i|
            pg = Paginator.new(page, slice, i + 1, slices.size)
            jobs << layout_job(pg.output_path, origin, layout, page, format, pg)
          end
        else
          jobs << layout_job(rel, origin, layout, page, format, Paginator.new(page, page.pages, 1, 1))
        end
      end
    end

    # Jobs are created through these helpers so that each proc closes over
    # its own parameters rather than over loop variables.
    private def body_job(rel : String, origin : String, page : Page, format : String) : Job
      Job.new(rel, origin, ->{ body(page, format) })
    end

    private def layout_job(rel : String, origin : String, layout : String, page : Page, format : String, pg : Paginator) : Job
      Job.new(rel, origin, ->{ render_layout(layout, page, body(page, format), pg) })
    end

    private def body(page : Page, format : String) : Bytes
      page.content[format]? || page.content["html"]? || Bytes.empty
    end

    private def render_layout(path : String, page : Page, body : Bytes, paginator : Paginator) : Bytes
      resolved = @registry.resolve(File.basename(path))
      vars = {
        "content"   => Crinja::Value.new(Crinja::SafeString.new(String.new(body))),
        "paginator" => Crinja::Value.new(paginator),
      }
      ctx = Chain::Context.new(@site, @env, page, vars, origin: path)
      @registry.process(read(path), resolved, ctx)
    end

    # ---- aliases ---------------------------------------------------------

    # Each alias becomes a small redirect page. `layouts/alias.html.j2`, if
    # present, replaces the built-in one; it gets `page` (the target) and
    # `alias` (the old url).
    private def plan_aliases(page : Page, jobs : Array(Job))
      page.aliases.each { |a| jobs << alias_job(page, a) }
    end

    private def alias_job(page : Page, a : String) : Job
      rel = a.strip('/')
      rel = File.join(rel, "index.html") if a.ends_with?('/') || File.extname(rel).empty?
      Job.new(rel, "alias #{a} of #{page.dir}", ->{ render_alias(page, a) })
    end

    private def render_alias(page : Page, a : String) : Bytes
      if layout = @layouts[{"", "alias", "html"}]?
        pg = Paginator.new(page, page.pages, 1, 1)
        vars = {"alias" => Crinja::Value.new(a), "content" => Crinja::Value.new(""), "paginator" => Crinja::Value.new(pg)}
        ctx = Chain::Context.new(@site, @env, page, vars, origin: layout)
        @registry.process(read(layout), @registry.resolve(File.basename(layout)), ctx)
      else
        alias_html(page).to_slice
      end
    end

    private def alias_html(page : Page) : String
      url = HTML.escape(page.url)
      title = HTML.escape(page.title)
      <<-HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>#{title}</title>
        <link rel="canonical" href="#{HTML.escape(page.permalink)}">
        <meta http-equiv="refresh" content="0; url=#{url}"></head>
        <body><a href="#{url}">#{title}</a></body></html>

        HTML
    end

    # ---- resources and static files --------------------------------------

    private def plan_resource(r : Resource, jobs : Array(Job))
      jobs << resource_job(r)
    end

    private def resource_job(r : Resource) : Job
      target = File.join(r.page.output_dir, r.rel_path)
      if r.resolved.passthrough?
        Job.new(target, r.source_path, ->{ read(r.source_path) })
      else
        Job.new(target, r.source_path, ->{
          ctx = Chain::Context.new(@site, @env, r.page, origin: r.source_path)
          @registry.process(read(r.source_path), r.resolved, ctx)
        })
      end
    end

    # Static files from the site and its themes go through the extension
    # chain like resources (most have no processor extension and are copied
    # verbatim). The site's copy of an output path wins over a theme's.
    # Files and directories whose name starts with `_` are private, such as
    # Sass partials, and are never output.
    private def plan_static(jobs : Array(Job))
      files = {} of String => Job
      @site.config.static_dirs.each do |dir|
        next unless Dir.exists?(dir)
        Dir.glob(File.join(dir, "**", "*"), match: File::MatchOptions::DotFiles).sort.each do |path|
          next unless File.file?(path)
          rel = path[(dir.size + 1)..]
          next if rel.split('/').any?(&.starts_with?('_'))
          resolved = @registry.resolve(File.basename(rel))
          target = File.join(File.dirname(rel), resolved.output_name).lchop("./")
          files[target] = static_job(target, path, resolved) unless files.has_key?(target)
        end
      end
      files.each_value { |j| jobs << j }
    end

    private def static_job(rel : String, path : String, resolved : Chain::Resolved) : Job
      if resolved.passthrough?
        Job.new(rel, path, ->{ read(path) })
      else
        Job.new(rel, path, ->{
          ctx = Chain::Context.new(@site, @env, nil, origin: path)
          @registry.process(read(path), resolved, ctx)
        })
      end
    end

    # ---- output ----------------------------------------------------------

    private def read(path : String) : Bytes
      File.open(path, &.getb_to_end)
    end

    private def write(rel : String, content : Bytes)
      path = File.join(@output_dir, rel)
      if File.file?(path) && File.size(path) == content.size && read(path) == content
        File.touch(path) if @touch
        @unchanged += 1
        return
      end
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      @changed += 1
    end
  end
end
