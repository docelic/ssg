require "yaml"
require "markd"

module SSG
  class Config
    getter title : String
    getter base_url : String
    # Theme names, highest priority first. Each lives in themes/<name>/.
    getter themes : Array(String)
    getter themes_dir : String
    getter permalinks : Hash(String, String)
    getter cascade : FrontMatter::Data
    # Highlighting theme name, nil when highlighting is off.
    getter highlight_theme : String?
    getter? line_numbers : Bool
    # nested | expanded | compact | compressed
    getter sass_style : String
    getter taxonomies : Array(String)
    getter content_dir : String
    getter layouts_dir : String
    getter static_dir : String
    getter data_dir : String
    getter paginate : Int32
    getter markdown : Markd::Options
    getter output_dir : String
    getter params : FrontMatter::Data
    getter root : String

    DEFAULT_TAXONOMIES = ["tags", "categories"]

    def initialize(@root : String, data : FrontMatter::Data = FrontMatter::Data.new) # ameba:disable Metrics/CyclomaticComplexity
      @title = data["title"]?.try(&.as_s?) || ""
      @base_url = normalize_base_url(data["base_url"]?.try(&.as_s?) || "/")
      @permalinks = data["permalinks"]?.try(&.as_h?).try { |h| h.to_h { |k, v| {k.to_s, v.as_s} } } || {} of String => String
      @cascade = data["cascade"]?.try(&.as_h?).try(&.to_h { |k, v| {k.to_s, v} }) || FrontMatter::Data.new
      @highlight_theme = "default-dark"
      @line_numbers = false
      @taxonomies = data["taxonomies"]?.try(&.as_a?).try(&.map(&.as_s)) || DEFAULT_TAXONOMIES
      @content_dir = File.join(@root, data["content_dir"]?.try(&.as_s?) || "content")
      @layouts_dir = File.join(@root, data["layouts_dir"]?.try(&.as_s?) || "layouts")
      @static_dir = File.join(@root, data["static_dir"]?.try(&.as_s?) || "static")
      @data_dir = File.join(@root, data["data_dir"]?.try(&.as_s?) || "data")
      @paginate = data["paginate"]?.try(&.as_i?) || 0
      @markdown = markdown_options(data["markdown"]?)
      @sass_style = data["sass"]?.try(&.as_h?).try(&.[YAML::Any.new("style")]?).try(&.as_s?) || "nested"
      @output_dir = File.expand_path(data["output_dir"]?.try(&.as_s?) || "public", @root)
      @themes_dir = File.join(@root, data["themes_dir"]?.try(&.as_s?) || "themes")
      @themes = case t = data["theme"]?.try(&.raw)
                when String then [t]
                when Array  then t.map(&.raw.to_s)
                else             [] of String
                end
      @themes.each do |name|
        dir = File.join(@themes_dir, name)
        raise Error.new("theme not found: #{dir}") unless Dir.exists?(dir)
      end
      @params = data["params"]?.try(&.as_h?).try { |h| h.transform_keys(&.to_s) } || FrontMatter::Data.new
    end

    # Directories to search, highest priority first: the site's own, then
    # each theme's, in the order themes are listed.
    def layout_dirs : Array(String)
      [@layouts_dir] + @themes.map { |t| File.join(@themes_dir, t, "layouts") }
    end

    def static_dirs : Array(String)
      [@static_dir] + @themes.map { |t| File.join(@themes_dir, t, "static") }
    end

    def data_dirs : Array(String)
      [@data_dir] + @themes.map { |t| File.join(@themes_dir, t, "data") }
    end

    def self.load(root : String, file : String = "config.yml") : Config
      path = File.join(root, file)
      data = FrontMatter::Data.new
      if File.exists?(path)
        parsed = YAML.parse(File.read(path))
        parsed.as_h?.try &.each { |k, v| data[k.to_s] = v }
      end
      new(root, data)
    rescue e : YAML::ParseException
      raise Error.new("#{file}: #{e.message}", cause: e)
    end

    def base_url=(url : String)
      @base_url = normalize_base_url(url)
    end

    # `markdown:` block: boolean markd options by name, plus `highlight`
    # (false, or a theme name) and `line_numbers`.
    private def markdown_options(any : YAML::Any?) : Markd::Options # ameba:disable Metrics/CyclomaticComplexity
      o = Markd::Options.new
      any.try(&.as_h?).try &.each do |k, v|
        flag = v.as_bool? || false
        case k.to_s
        when "highlight"
          @highlight_theme = v.as_s? || (flag ? "default-dark" : nil)
          next
        when "line_numbers"
          @line_numbers = flag
          next
        when "gfm"         then o.gfm = flag
        when "smart"       then o.smart = flag
        when "safe"        then o.safe = flag
        when "source_pos"  then o.source_pos = flag
        when "prettyprint" then o.prettyprint = flag
        when "emoji"       then o.emoji = flag
        when "tagfilter"   then o.tagfilter = flag
        when "autolink"    then o.autolink = flag
        else                    raise Error.new("config: unknown markdown option #{k}")
        end
      end
      o
    end

    private def normalize_base_url(url : String) : String
      url.ends_with?('/') ? url : url + "/"
    end
  end
end
