require "yaml"

module SSG
  # YAML front matter delimited by `---` lines at the very start of the file.
  module FrontMatter
    alias Data = Hash(String, YAML::Any)

    DELIM = "---"

    # Returns {data, body}. Files without front matter yield an empty hash
    # and the unchanged content.
    def self.split(source : String, origin : String = "<string>") : {Data, String}
      return {Data.new, source} unless source.starts_with?(DELIM)

      lines = source.lines(chomp: false)
      return {Data.new, source} unless lines[0].rstrip == DELIM

      close = (1...lines.size).find { |i| lines[i].rstrip == DELIM }
      raise Error.new("#{origin}: unterminated front matter") unless close

      yaml = lines[1...close].join
      body = lines[(close + 1)..].join

      data = Data.new
      parsed = YAML.parse(yaml)
      if hash = parsed.as_h?
        hash.each { |k, v| data[k.to_s] = v }
      elsif !parsed.raw.nil?
        raise Error.new("#{origin}: front matter must be a mapping")
      end
      {data, body}
    rescue e : YAML::ParseException
      raise Error.new("#{origin}: invalid front matter: #{e.message}", cause: e)
    end
  end
end
