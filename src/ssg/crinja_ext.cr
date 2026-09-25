require "crinja"

# Two adjustments to Crinja's value comparison, used by `sort`, `min`, `max`
# and the comparison operators:
#   * Time values are comparable (needed for sort(attribute="date")).
#   * Missing values (nil, undefined) compare greater than anything, so a
#     sort by an attribute some pages lack puts those pages last instead of
#     raising.
struct Crinja::Value
  private def compare(a, b) # ameba:disable Metrics/CyclomaticComplexity
    a_missing = a.nil? || a.is_a?(Undefined)
    b_missing = b.nil? || b.is_a?(Undefined)
    if a_missing || b_missing
      (a_missing ? 1 : 0) - (b_missing ? 1 : 0)
    elsif a.is_a?(Time) && b.is_a?(Time)
      a <=> b
    elsif a.is_a?(Array)
      if b.is_a?(Array)
        compare_array(a, b)
      else
        raise TypeError.new "Cannot compare Array with #{b.class}"
      end
    elsif a.is_a?(Bool) || b.is_a?(Bool)
      raise TypeError.new "Cannot compare Bool value"
    elsif a.is_a?(Number) && b.is_a?(Number)
      a <=> b
    elsif a.is_a?(String | SafeString) || b.is_a?(String | SafeString)
      a.to_s <=> b.to_s
    else
      raise TypeError.new("cannot compare #{a.class} with #{b.class}")
    end
  end
end
