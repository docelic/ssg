require "crinja"

module SSG
  class Site
    include Crinja::Object

    getter config : Config
    getter registry : Chain::Registry
    getter pages = [] of Page
    getter home : Page
    getter taxonomy_pages = {} of String => Page
    getter? drafts : Bool
    # data/*.yml|yaml|json, nested by directory, as site.data.<name>
    getter data = FrontMatter::Data.new

    @by_dir = {} of String => Page
    @term_index = {} of String => Hash(String, Page)

    # A scanned content directory, before classification.
    private class Tree
      getter name : String
      getter rel : String
      getter abs : String
      getter index_files = [] of String
      getter page_files = [] of String
      getter files = [] of String
      getter subtrees = [] of Tree

      def initialize(@name, @rel, @abs)
      end

      def page? : Bool
        !@index_files.empty?
      end

      def has_pages? : Bool
        page? || !@page_files.empty? || @subtrees.any?(&.has_pages?)
      end
    end

    def initialize(@config, @registry = Processors.default_registry(config), @drafts = false)
      @home = uninitialized Page
      load
    end

    private def load
      dir = @config.content_dir
      raise Error.new("content directory not found: #{dir}") unless Dir.exists?(dir)

      load_data
      tree = scan(dir, "")
      home = tree.page? ? real_page(tree, nil) : nil
      @home = home || register(Page.new(self, "", Page::Kind::List))
      populate(tree, @home)
      # Taxonomies are built from cascaded terms, and the pages they
      # synthesize need cascaded defaults in turn; the second pass only
      # touches pages that did not exist during the first.
      apply_cascade(@home, @config.cascade)
      build_taxonomies
      apply_cascade(@home, @config.cascade)
      assign_kinds_and_sort
    end

    # ---- data ------------------------------------------------------------

    private def load_data
      root = {} of YAML::Any => YAML::Any
      @config.data_dirs.reverse_each { |dir| load_data_dir(dir, root) if Dir.exists?(dir) }
      root.each { |k, v| @data[k.as_s] = v }
    end

    # Later calls override earlier ones file by file.
    private def load_data_dir(dir : String, root : Hash(YAML::Any, YAML::Any))
      Dir.glob(File.join(dir, "**", "*.{yml,yaml,json}")).sort.each do |path|
        segments = path[(dir.size + 1)..].sub(/\.(yml|yaml|json)$/, "").split('/')
        hash = root
        segments[0...-1].each do |seg|
          key = YAML::Any.new(seg)
          hash = (hash[key]?.try(&.as_h?) || (hash[key] = YAML::Any.new({} of YAML::Any => YAML::Any)).as_h)
        end
        hash[YAML::Any.new(segments.last)] = YAML.parse(File.read(path))
      rescue e : YAML::ParseException
        raise Error.new("#{path}: #{e.message}", cause: e)
      end
    end

    # ---- scanning --------------------------------------------------------

    private def scan(abs : String, rel : String) : Tree
      tree = Tree.new(File.basename(abs), rel, abs)
      Dir.children(abs).sort.each do |entry|
        next if entry.starts_with?('.')
        path = File.join(abs, entry)
        if File.directory?(path)
          tree.subtrees << scan(path, rel.empty? ? entry : "#{rel}/#{entry}")
          next
        end
        resolved = @registry.resolve(entry)
        if resolved.base == "index" && resolved.format
          tree.index_files << entry
        elsif resolved.processed? && resolved.format == "html"
          tree.page_files << entry
        else
          tree.files << entry
        end
      end
      tree
    end

    # ---- classification --------------------------------------------------

    # Fills a page directory: resources, single-file child pages, subtrees.
    private def populate(tree : Tree, page : Page)
      tree.files.each do |f|
        add_resource(page, File.join(tree.abs, f), f)
      end
      tree.page_files.each do |f|
        add_single_file_page(page, File.join(tree.abs, f), tree.rel)
      end
      tree.subtrees.each do |sub|
        if sub.page?
          child = real_page(sub, page)
          populate(sub, child) if child
        elsif sub.has_pages?
          child = register Page.new(self, sub.rel, Page::Kind::List)
          link(child, page)
          populate(sub, child)
        else
          add_resource_tree(page, sub)
        end
      end
    end

    private def real_page(tree : Tree, parent : Page?) : Page?
      variants = tree.index_files.map do |f|
        path = File.join(tree.abs, f)
        resolved = @registry.resolve(f)
        data, body = FrontMatter.split(File.read(path), path)
        Variant.new(path, resolved, data, body)
      end
      formats = variants.map(&.format)
      if dup = formats.find { |f| formats.count(f) > 1 }
        raise Error.new("#{tree.abs}: more than one index file produces format #{dup}")
      end
      primary = variants.find { |v| v.format == "html" } || variants.first
      page = Page.new(self, tree.rel, Page::Kind::Page, primary.data, variants)
      return if page.draft? && !drafts?
      register page
      link(page, parent) if parent
      page
    end

    private def add_single_file_page(parent : Page, path : String, parent_rel : String)
      name = File.basename(path)
      resolved = @registry.resolve(name)
      base = resolved.base
      dir = parent_rel.empty? ? base : "#{parent_rel}/#{base}"
      data, body = FrontMatter.split(File.read(path), path)
      page = Page.new(self, dir, Page::Kind::Page, data, [Variant.new(path, resolved, data, body)])
      return if page.draft? && !drafts?
      register page
      link(page, parent)
    end

    private def add_resource(page : Page, path : String, rel : String)
      resolved = @registry.resolve(File.basename(path))
      out_rel = File.join(File.dirname(rel), resolved.output_name).lchop("./")
      page.resources << Resource.new(path, out_rel, resolved, page)
    end

    private def add_resource_tree(page : Page, tree : Tree)
      prefix = page.dir.empty? ? tree.rel : tree.rel[(page.dir.size + 1)..]
      (tree.files + tree.page_files + tree.index_files).each do |f|
        add_resource(page, File.join(tree.abs, f), "#{prefix}/#{f}")
      end
      tree.subtrees.each { |s| add_resource_tree(page, s) }
    end

    private def register(page : Page) : Page
      if other = @by_dir[page.dir]?
        raise Error.new("two pages map to #{page.url}: #{describe(other)} and #{describe(page)}")
      end
      @by_dir[page.dir] = page
      @pages << page
      page
    end

    private def describe(page : Page) : String
      page.variants.first?.try(&.source_path) || "synthetic #{page.kind} page"
    end

    private def link(child : Page, parent : Page)
      child.parent = parent
      parent.children << child
    end

    # ---- cascade ---------------------------------------------------------

    # `cascade:` in config or in a page's front matter supplies defaults to
    # that page and everything below it. A page's own keys always win.
    private def apply_cascade(page : Page, inherited : FrontMatter::Data)
      own = page.data["cascade"]?.try(&.as_h?).try(&.to_h { |k, v| {k.to_s, v} }) || FrontMatter::Data.new
      effective = inherited.merge(own)
      effective.each { |k, v| page.data[k] = v unless page.data.has_key?(k) }
      page.children.each { |c| apply_cascade(c, effective) }
    end

    # ---- taxonomies ------------------------------------------------------

    private def build_taxonomies
      @config.taxonomies.each do |tax|
        terms = {} of String => Array(Page)
        @pages.each do |p|
          next if p.synthetic?
          p.term_values(tax).each { |t| (terms[t] ||= [] of Page) << p }
        end
        next if terms.empty?

        tax_page = @by_dir[tax]? || register(Page.new(self, tax, Page::Kind::List))
        tax_page.taxonomy = tax
        link(tax_page, @home) unless tax_page.parent
        @taxonomy_pages[tax] = tax_page
        index = @term_index[tax] = {} of String => Page

        terms.keys.sort!.each do |term|
          dir = "#{tax}/#{Site.slugify(term)}"
          tp = @by_dir[dir]? || register(Page.new(self, dir, Page::Kind::List))
          tp.taxonomy = tax
          tp.term = term
          tp.term_pages.concat(terms[term])
          link(tp, tax_page) unless tp.parent
          index[term] = tp
        end
      end
    end

    def term_pages(taxonomy : String, terms : Array(String)) : Array(Page)
      idx = @term_index[taxonomy]? || return [] of Page
      terms.compact_map { |t| idx[t]? }
    end

    def self.slugify(s : String) : String
      s.downcase.gsub(/[^a-z0-9._-]+/, "-").strip('-')
    end

    # ---- finishing -------------------------------------------------------

    private def assign_kinds_and_sort
      @home.kind = Page::Kind::List
      @pages.each do |p|
        p.kind = Page::Kind::List if !p.children.empty? || p.taxonomy
        p.sort_children!
        p.term_pages.sort! { |a, b| (b.date || Time::UNIX_EPOCH) <=> (a.date || Time::UNIX_EPOCH) }
      end
    end

    # ---- queries ---------------------------------------------------------

    def absolute_url(path : String) : String
      @config.base_url + path.lchop('/')
    end

    def regular_pages : Array(Page)
      @pages.select(&.kind.page?)
    end

    # Top-level sections, excluding taxonomies.
    def sections : Array(Page)
      @home.children.select { |c| c.kind.list? && c.taxonomy.nil? }
    end

    # Find a page by content path: "blog/hello", "blog/hello/index.md",
    # "blog/hello.md", "/blog/hello/". A bare name with no slash also
    # matches a page anywhere by slug or directory name, if unambiguous.
    def find(ref : String) : Page?
      ref = ref.strip('/')
      return @home if ref.empty?
      if page = find_by_path(ref)
        return page
      end
      return if ref.includes?('/')
      matches = @pages.select { |p| !p.dir.empty? && (p.slug == ref || File.basename(p.dir) == ref) }
      raise Error.new("ambiguous reference #{ref.inspect}: #{matches.map(&.url).join(", ")}") if matches.size > 1
      matches.first?
    end

    private def find_by_path(ref : String) : Page?
      name = File.basename(ref)
      parent = File.dirname(ref)
      parent = "" if parent == "."
      resolved = @registry.resolve(name)
      dir = if resolved.base == "index" && resolved.format
              parent
            elsif resolved.processed? && resolved.format
              parent.empty? ? resolved.base : "#{parent}/#{resolved.base}"
            else
              ref
            end
      @by_dir[dir]?
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      name = attr.to_string
      value = case name
              when "title"         then @config.title
              when "base_url"      then @config.base_url
              when "params"        then Values.dict(@config.params)
              when "data"          then Values.dict(@data)
              when "home"          then @home
              when "pages"         then @pages
              when "regular_pages" then regular_pages
              when "sections"      then sections
              when "taxonomies"
                dict = Crinja::Dictionary.new
                @taxonomy_pages.each { |k, v| dict[Crinja::Value.new(k)] = Crinja::Value.new(v) }
                dict
              else
                if v = @config.params[name]?
                  return Values.from_yaml(v)
                end
                Crinja::Undefined.new(name)
              end
      Crinja::Value.new(value)
    end

    def crinja_call(name : String) : Crinja::Callable | Crinja::Callable::Proc?
      case name
      when "page"
        ->(args : Crinja::Arguments) { Crinja::Value.new(find(args.varargs[0].to_s)) }
      end
    end
  end
end
