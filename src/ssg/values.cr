require "crinja"
require "yaml"
require "json"

module SSG
  # Conversions from YAML front matter into native Crinja values, so that
  # `{% for x in page.params.list %}` and friends work as in plain Jinja.
  module Values
    def self.from_yaml(any : YAML::Any) : Crinja::Value
      case raw = any.raw
      when Hash
        dict = Crinja::Dictionary.new
        raw.each { |k, v| dict[Crinja::Value.new(k.raw.to_s)] = from_yaml(v) }
        Crinja::Value.new(dict)
      when Array
        Crinja::Value.new(raw.map { |v| from_yaml(v).as(Crinja::Value) })
      when Set
        Crinja::Value.new(raw.map { |v| from_yaml(v).as(Crinja::Value) })
      when Bytes
        Crinja::Value.new(String.new(raw))
      when Nil, Bool, Int64, Float64, String, Time
        Crinja::Value.new(raw)
      else
        Crinja::Value.new(raw.to_s)
      end
    end

    # Plain JSON for a template value, for scripts and data files.
    def self.json(value : Crinja::Value, io : JSON::Builder)
      case raw = value.raw
      when Nil, Crinja::Undefined then io.null
      when Bool                   then io.bool(raw)
      when Int32, Int64, Float64  then io.number(raw)
      when String                 then io.string(raw)
      when Time                   then io.string(raw.to_rfc3339)
      when Array(Crinja::Value)   then io.array { raw.each { |v| json(v, io) } }
      when Crinja::Dictionary     then io.object { raw.each { |k, v| io.field(k.to_s) { json(v, io) } } }
      else                             io.string(raw.to_s)
      end
    end

    def self.dict(data : FrontMatter::Data) : Crinja::Value
      dict = Crinja::Dictionary.new
      data.each { |k, v| dict[Crinja::Value.new(k)] = from_yaml(v) }
      Crinja::Value.new(dict)
    end

    # Front matter dates may be YAML timestamps (already Time) or strings.
    def self.time?(any : YAML::Any?) : Time?
      return nil unless any
      case raw = any.raw
      when Time   then raw
      when String then parse_time(raw)
      else             nil
      end
    end

    def self.parse_time(s : String) : Time?
      Time.parse_rfc3339(s)
    rescue Time::Format::Error
      begin
        Time.parse(s, "%F", Time::Location::UTC)
      rescue Time::Format::Error
        nil
      end
    end
  end
end
