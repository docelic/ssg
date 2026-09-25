module SSG
  # One-time translation of Hugo shortcode calls into Jinja macro calls.
  #
  #   {{< L "https://x" "text" >}}      -> {{ L("https://x", "text") }}
  #   {{< fig src="a.png" >}}           -> {{ fig(src="a.png") }}
  #   {{< bq cite="me" >}}text{{< /bq >}} -> {% call bq(cite="me") %}text{% endcall %}
  #
  # Both `{{<` and `{{%` are accepted. Front matter is left untouched.
  module HugoConvert
    TAG = /\{\{[<%]\s*(\/?)([A-Za-z_][\w-]*)\s*(.*?)\s*[>%]\}\}/
    ARG = /\G\s*(?:([A-Za-z_][\w-]*)=)?(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^\s"']+))/

    record Tag, name : String, args : String, closing : Bool, range : Range(Int32, Int32)

    def self.convert(source : String) : String
      tags = [] of Tag
      source.scan(TAG) do |m|
        tags << Tag.new(m[2], m[3], m[1] == "/", m.begin(0)...m.end(0))
      end
      return source if tags.empty?

      out = String::Builder.new
      pos = 0
      i = 0
      while i < tags.size
        tag = tags[i]
        out << source[pos...tag.range.begin]
        raise Error.new("unmatched closing shortcode {{< /#{tag.name} >}}") if tag.closing
        close = tags[i + 1]?
        if close && close.closing && close.name == tag.name
          inner = source[tag.range.end...close.range.begin]
          out << "{% call #{tag.name}(#{arguments(tag.args)}) %}" << inner << "{% endcall %}"
          pos = close.range.end
          i += 2
        else
          out << "{{ #{tag.name}(#{arguments(tag.args)}) }}"
          pos = tag.range.end
          i += 1
        end
      end
      out << source[pos..]
      out.to_s
    end

    private def self.arguments(args : String) : String
      list = [] of String
      pos = 0
      while (m = ARG.match(args, pos))
        pos = m.end
        value = m[2]? || m[3]?.try(&.gsub("\\'", "'")) || m[4]? || ""
        literal = %("#{value.gsub("\\", "\\\\").gsub('"', "\\\"")}")
        list << (m[1]? ? "#{m[1]}=#{literal}" : literal)
      end
      list.join(", ")
    end

    # Convert files. Without *write*, print to stdout. With it, replace each
    # `x.md` by a converted `x.md.j2` (a `.j2` file is converted in place).
    def self.run(paths : Array(String), write : Bool)
      paths.each do |path|
        converted = convert(File.read(path))
        if write
          target = path.ends_with?(".j2") ? path : path + ".j2"
          File.write(target, converted)
          File.delete(path) unless target == path
          STDERR.puts "#{path} -> #{target}"
        else
          STDOUT << converted
        end
      end
    end
  end
end
