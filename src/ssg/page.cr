require "crinja"
require "html"

module SSG
  # A file that belongs to a page directory and is emitted next to the page.
  class Resource
    include Crinja::Object

    getter source_path : String
    # Path relative to the page directory, using output (not source) names.
    getter rel_path : String
    getter resolved : Chain::Resolved
    getter page : Page

    def initialize(@source_path, @rel_path, @resolved, @page)
    end

    def format : String?
      @resolved.format
    end

    def url : String
      @page.url + @rel_path
    end

    def permalink : String
      @page.site.absolute_url(url)
    end

    def name : String
      File.basename(@rel_path)
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      value = case attr.to_string
              when "url"       then url
              when "permalink" then permalink
              when "name"      then name
              when "path"      then rel_path
              when "format"    then format
              else                  Crinja::Undefined.new(attr.to_s)
              end
      Crinja::Value.new(value)
    end
  end

  # One source file of a page: index.md, index.xml.j2, ...
  class Variant
    getter source_path : String
    getter resolved : Chain::Resolved
    getter data : FrontMatter::Data
    getter body : String

    def initialize(@source_path, @resolved, @data, @body)
    end

    def format : String
      @resolved.format || raise Error.new("#{@source_path}: no output format")
    end
  end

  # A per-page scratch space: content (shortcodes) writes to it while it
  # renders, layouts read it afterwards.
  class Store
    include Crinja::Object

    getter data = {} of String => Crinja::Value

    def get(key : String) : Crinja::Value
      @data[key]? || Crinja::Value.new(Crinja::Undefined.new(key))
    end

    def set(key : String, value : Crinja::Value)
      @data[key] = value
    end

    def append(key : String, value : Crinja::Value)
      list = @data[key]?.try(&.raw).as?(Array(Crinja::Value))
      unless list
        list = [] of Crinja::Value
        @data[key] = Crinja::Value.new(list)
      end
      list << value
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      get(attr.to_string)
    end

    def crinja_call(name : String) : Crinja::Callable | Crinja::Callable::Proc?
      case name
      when "get"
        ->(a : Crinja::Arguments) { get(a.varargs[0].to_s) }
      when "set"
        ->(a : Crinja::Arguments) { set(a.varargs[0].to_s, a.varargs[1]); Crinja::Value.new("") }
      when "append"
        ->(a : Crinja::Arguments) { append(a.varargs[0].to_s, a.varargs[1]); Crinja::Value.new("") }
      end
    end
  end

  record Heading, level : Int32, id : String, text : String do
    include Crinja::Object

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      value = case attr.to_string
              when "level" then level
              when "id"    then id
              when "text"  then text
              else              Crinja::Undefined.new(attr.to_s)
              end
      Crinja::Value.new(value)
    end
  end

  record Link, url : String, text : String do
    include Crinja::Object

    def external? : Bool
      url.includes?("://")
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      value = case attr.to_string
              when "url"      then url
              when "text"     then text
              when "external" then external?
              else                 Crinja::Undefined.new(attr.to_s)
              end
      Crinja::Value.new(value)
    end
  end

  class Page
    include Crinja::Object

    # A page either lists other pages or it doesn't. The home page, sections,
    # taxonomies and terms are all lists; what they list differs.
    enum Kind
      Page
      List

      def to_s : String
        super.downcase
      end
    end

    getter site : Site
    # Directory relative to the content root: "" for home, "blog/hello" ...
    getter dir : String
    property kind : Kind
    getter variants = [] of Variant
    getter resources = [] of Resource
    getter children = [] of Page
    property parent : Page?
    getter data : FrontMatter::Data
    # Rendered body per format, filled by the renderer.
    getter content = {} of String => Bytes
    getter store = Store.new
    # Set on taxonomy pages (/tags/) and term pages (/tags/foo/).
    property taxonomy : String?
    property term : String?
    getter term_pages = [] of Page

    def initialize(@site, @dir, @kind, @data = FrontMatter::Data.new, @variants = [] of Variant,
                   @taxonomy = nil, @term = nil)
    end

    def synthetic? : Bool
      @variants.empty?
    end

    def home? : Bool
      @dir.empty?
    end

    def title : String
      if t = @data["title"]?.try(&.as_s?)
        t
      elsif term = @term
        term
      elsif tax = @taxonomy
        tax.capitalize
      elsif home?
        @site.config.title
      else
        File.basename(@dir).tr("-_", "  ").capitalize
      end
    end

    def date : Time?
      Values.time?(@data["date"]?)
    end

    def draft? : Bool
      @data["draft"]?.try(&.as_bool?) || false
    end

    def weight : Int64?
      @data["weight"]?.try(&.as_i64?)
    end

    def layout : String?
      @data["layout"]?.try(&.as_s?)
    end

    def slug : String
      @data["slug"]?.try(&.as_s?) || File.basename(@dir)
    end

    # Items per page for list pages; 0 disables pagination.
    def paginate : Int32
      @data["paginate"]?.try(&.as_i?) || @site.config.paginate
    end

    # Top-level section name, "" for the home page.
    def section : String
      @dir.split('/').first? || ""
    end

    # Output directory relative to the output root; also the URL path.
    # In order: `url` from front matter; a `permalinks` pattern for the
    # section (regular pages only); else the parent's output directory plus
    # this page's slug, so a section's slug applies to everything below it.
    def output_dir : String
      return "" if home?
      if u = @data["url"]?.try(&.as_s?)
        u = u.strip('/')
        return u unless file_url?
        d = File.dirname(u)
        return d == "." ? "" : d
      end
      if @kind.page? && (pattern = @site.config.permalinks[section]?)
        return expand_permalink(pattern).strip('/')
      end
      base = parent.try(&.output_dir) || ""
      base.empty? ? slug : "#{base}/#{slug}"
    end

    PERMALINK_TOKEN = /:(year|month|day|slug|section|title|filename)/

    private def expand_permalink(pattern : String) : String
      pattern.gsub(PERMALINK_TOKEN) do
        case $1
        when "year"     then dated.to_s("%Y")
        when "month"    then dated.to_s("%m")
        when "day"      then dated.to_s("%d")
        when "slug"     then slug
        when "section"  then section
        when "title"    then Site.slugify(title)
        when "filename" then File.basename(@dir)
        else                 $0
        end
      end
    end

    private def dated : Time
      date || raise Error.new("#{@dir}: permalink pattern uses a date but the page has none")
    end

    # Old urls that should redirect here, from `aliases:` in front matter.
    def aliases : Array(String)
      case v = @data["aliases"]?.try(&.raw)
      when Array  then v.map(&.raw.to_s)
      when String then [v]
      else             [] of String
      end
    end

    # Formats this page is rendered in, from `outputs:` in front matter.
    # Nil means every format that has a variant or a matching layout; an
    # empty list produces no output at all while the page stays in the
    # site graph. The key never adds a format, it only restricts.
    def outputs : Array(String)?
      case v = @data["outputs"]?.try(&.raw)
      when Array  then v.map(&.raw.to_s)
      when String then [v]
      when Bool   then v ? nil : [] of String
      end
    end

    # `url: /404.html` names a file instead of a directory: the page's
    # output of that format goes exactly there, and no other formats are
    # produced for it.
    def file_url? : Bool
      !!(@data["url"]?.try(&.as_s?).try { |u| u =~ /\.[A-Za-z0-9]+$/ })
    end

    def url : String
      return "/" + @data["url"].as_s.lstrip('/') if file_url?
      out = output_dir
      out.empty? ? "/" : "/#{out}/"
    end

    # Where the output for *format* goes, relative to the output root.
    def output_path(format : String) : String
      if file_url? && File.extname(url).lchop('.') == format
        url.lchop('/')
      else
        File.join(output_dir, "index.#{format}")
      end
    end

    def permalink : String
      @site.absolute_url(url)
    end

    # What this page lists: tagged pages for a term, child pages otherwise.
    def pages : Array(Page)
      @term ? @term_pages : @children
    end

    def regular_pages : Array(Page)
      pages.select(&.kind.page?)
    end

    def siblings : Array(Page)
      (parent.try(&.children) || [] of Page).select(&.kind.page?)
    end

    def next : Page?
      s = siblings
      i = s.index(self)
      i && i > 0 ? s[i - 1] : nil
    end

    def prev : Page?
      s = siblings
      i = s.index(self)
      i && i < s.size - 1 ? s[i + 1] : nil
    end

    # Values of a taxonomy given in front matter, e.g. tags.
    def term_values(taxonomy : String) : Array(String)
      case v = @data[taxonomy]?.try(&.raw)
      when Array  then v.map(&.raw.to_s)
      when String then [v]
      when Nil    then [] of String
      else             [v.to_s]
      end
    end

    # Term pages this page is filed under, for one taxonomy.
    def terms_for(taxonomy : String) : Array(Page)
      @site.term_pages(taxonomy, term_values(taxonomy))
    end

    def content_string(format : String) : String
      String.new(@content[format]? || Bytes.empty)
    end

    HEADING = /<h([1-6])(?:\s[^>]*?id="([^"]*)")?[^>]*>(.*?)<\/h\1>/m
    LINK    = /<a\s[^>]*?href="([^"]*)"[^>]*>(.*?)<\/a>/m
    PARA    = /<p[^>]*>(.*?)<\/p>/m

    # Headings of the html content, in document order, for building a TOC.
    def headings : Array(Heading)
      content_string("html").scan(HEADING).map do |m|
        text = strip_tags(m[3])
        Heading.new(m[1].to_i, m[2]? || Site.slugify(text), text)
      end
    end

    # Links in the html content, unique by url, in order of first appearance.
    def links : Array(Link)
      seen = Set(String).new
      content_string("html").scan(LINK).compact_map do |m|
        url = HTML.unescape(m[1])
        next if seen.includes?(url)
        seen << url
        Link.new(url, strip_tags(m[2]))
      end
    end

    # Front matter `summary`, else `description`, else the first paragraph.
    def summary : String
      @data["summary"]?.try(&.as_s?) ||
        @data["description"]?.try(&.as_s?) ||
        content_string("html").match(PARA).try { |m| strip_tags(m[1]) } ||
        ""
    end

    # Text content of the html, for search indexes and the like.
    def plain : String
      html = content_string("html").gsub(/<(script|style)[^>]*>.*?<\/\1>/m, "")
      strip_tags(html.gsub(/<\/(p|h[1-6]|li|div|tr|pre)>/i, "\n")).gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n")
    end

    private def strip_tags(html : String) : String
      HTML.unescape(html.gsub(/<[^>]*>/, "")).strip
    end

    def resource(rel : String) : Resource?
      @resources.find { |r| r.rel_path == rel }
    end

    # Weight ascending (unweighted last), then date descending, then title.
    def sort_children!
      @children.sort! do |a, b|
        cmp = (a.weight || Int64::MAX) <=> (b.weight || Int64::MAX)
        cmp = (b.date || Time::UNIX_EPOCH) <=> (a.date || Time::UNIX_EPOCH) if cmp == 0
        cmp = a.title <=> b.title if cmp == 0
        cmp
      end
    end

    def to_s(io)
      io << "#<Page " << url << " " << kind << ">"
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value # ameba:disable Metrics/CyclomaticComplexity
      name = attr.to_string
      value = case name
              when "title"         then title
              when "date"          then date
              when "url"           then url
              when "permalink"     then permalink
              when "path"          then @dir
              when "kind"          then @kind.to_s
              when "section"       then section
              when "slug"          then slug
              when "draft"         then draft?
              when "weight"        then weight
              when "content"       then Crinja::SafeString.new(content_string("html"))
              when "summary"       then summary
              when "plain"         then plain
              when "layout"        then layout
              when "params"        then Values.dict(@data)
              when "parent"        then parent
              when "children"      then @children
              when "pages"         then pages
              when "regular_pages" then regular_pages
              when "next"          then self.next
              when "prev"          then prev
              when "resources"     then @resources
              when "taxonomy"      then @taxonomy
              when "term"          then @term
              when "synthetic"     then synthetic?
              when "home"          then home?
              when "store"         then @store
              when "headings"      then headings
              when "links"         then links
              when "aliases"       then aliases
              when "outputs"       then outputs
              else
                # Fall through to front matter, so `page.author` works.
                if v = @data[name]?
                  return Values.from_yaml(v)
                end
                Crinja::Undefined.new(name)
              end
      Crinja::Value.new(value)
    end

    def crinja_call(name : String) : Crinja::Callable | Crinja::Callable::Proc?
      case name
      when "terms_for"
        ->(args : Crinja::Arguments) { Crinja::Value.new(terms_for(args.varargs[0].to_s)) }
      when "resource"
        ->(args : Crinja::Arguments) { Crinja::Value.new(resource(args.varargs[0].to_s)) }
      end
    end
  end

  # One page of a paginated list. Every list layout receives one, even when
  # the list is not paginated (then it holds all pages and total is 1).
  class Paginator
    include Crinja::Object

    getter page : Page
    getter pages : Array(Page)
    getter number : Int32
    getter total : Int32

    def initialize(@page, @pages, @number, @total)
    end

    def url(n : Int32 = @number) : String
      n == 1 ? @page.url : "#{@page.url}page/#{n}/"
    end

    def output_path : String
      n = @number
      n == 1 ? @page.output_path("html") : File.join(@page.output_dir, "page", n.to_s, "index.html")
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      value = case attr.to_string
              when "pages"    then @pages
              when "number"   then @number
              when "total"    then @total
              when "url"      then url
              when "first"    then @number == 1
              when "last"     then @number == @total
              when "prev_url" then @number > 1 ? url(@number - 1) : nil
              when "next_url" then @number < @total ? url(@number + 1) : nil
              when "urls"     then (1..@total).map { |n| url(n) }
              else                 Crinja::Undefined.new(attr.to_s)
              end
      Crinja::Value.new(value)
    end
  end
end
