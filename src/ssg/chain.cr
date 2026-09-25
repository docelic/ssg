# Extension-chain resolution and processing.
#
# A filename is `base.e1.e2...en`. Extensions are consumed from the right.
#
# * A *processor* is keyed by the extension it consumes. It either produces a
#   fixed format (Markdown produces html) or is *transparent* (Crinja: its
#   output has whatever format is named next).
# * A *converter* is keyed by a pair of formats (html -> pdf).
# * Any extension that is neither is a *format*.
#
# Resolution walks right to left:
#
#   1. Run every processor extension, tracking the current format: a producing
#      processor sets it, a transparent one leaves it.
#   2. If the format is still unknown, the next extension to the left names
#      it (or there is none).
#   3. If the next extension equals the current format, it is consumed.
#   4. While a converter exists from the current format to the next
#      extension, apply it and consume the extension.
#   5. Whatever is left is the base. Output is `base.<format>`.
#
#   test.html.j2        j2 (transparent), html          -> test.html
#   post.md             md produces html                -> post.html
#   post.md.j2          j2 then md                      -> post.html
#   report.pdf.html.md  md -> html, html -> pdf         -> report.pdf
#   report.pdf.md       md -> html, then html -> pdf    -> report.pdf
#   notes.txt.md        md -> html, then html -> txt    -> notes.txt
#   report.pdf.html     no processor; html -> pdf       -> report.pdf
#   archive.tar.gz      no converter gz -> tar          -> archive.tar.gz
#   logo.png            passthrough                     -> logo.png
#   Makefile.j2         j2, no format                   -> Makefile
#
# Everything above is decided from the filename alone, before reading a byte.
module SSG
  module Chain
    # What a step receives, besides the content.
    class Context
      getter site : Site
      getter page : Page?
      getter env : Crinja
      getter vars : Hash(String, Crinja::Value)
      # Human-readable origin of the content, for error messages.
      getter origin : String

      def initialize(@site, @env, @page = nil, @vars = {} of String => Crinja::Value, @origin = "<string>")
      end
    end

    # One transformation of content. Content is bytes so that binary formats
    # (pdf, images) flow through the same pipeline as text.
    abstract class Step
      abstract def call(input : Bytes, ctx : Context) : Bytes

      # Convenience for text-to-text steps.
      def call_text(input : Bytes, ctx : Context, &block : String -> String) : Bytes
        block.call(String.new(input)).to_slice
      end

      abstract def describe : String
    end

    abstract class Processor < Step
      # The extension this processor consumes, without a leading dot.
      abstract def ext : String

      # Format of the output, or nil when transparent.
      def produces : String?
        nil
      end

      def describe : String
        produces ? "#{ext} -> #{produces}" : ext
      end
    end

    abstract class Converter < Step
      abstract def from : String
      abstract def to : String

      def describe : String
        "#{from} -> #{to}"
      end
    end

    class Registry
      getter processors = {} of String => Processor
      getter converters = {} of {String, String} => Converter

      def register(p : Processor) : self
        @processors[p.ext] = p
        self
      end

      def register(c : Converter) : self
        @converters[{c.from, c.to}] = c
        self
      end

      def processor?(ext : String) : Bool
        @processors.has_key?(ext)
      end

      def converter?(from : String, to : String) : Converter?
        @converters[{from, to}]?
      end

      # Static resolution, from the filename alone.
      def resolve(filename : String) : Resolved
        parts = filename.split('.')
        steps = [] of Step
        format : String? = nil

        # 1. processors, right to left. parts[0] is always base.
        i = parts.size - 1
        while i > 0 && (p = @processors[parts[i]]?)
          steps << p
          format = p.produces || format
          i -= 1
        end

        # 2. transparent all the way: the next extension names the format.
        if format.nil? && !steps.empty? && i > 0
          format = parts[i]
          i -= 1
        end

        # 3. an explicitly spelled intermediate format is consumed.
        if format && i > 0 && parts[i] == format
          i -= 1
        end

        # No processors at all: the rightmost extension is the format.
        if steps.empty? && i > 0
          format = parts[i]
          i -= 1
        end

        # 4. converters, as far as they reach.
        while (f = format) && i > 0 && (c = converter?(f, parts[i]))
          steps << c
          format = parts[i]
          i -= 1
        end

        base = parts[0..i].join('.')
        output = format ? "#{base}.#{format}" : base
        Resolved.new(filename, base, output, format, steps)
      end

      # Run all steps in order.
      def process(content : Bytes, resolved : Resolved, ctx : Context) : Bytes
        resolved.steps.reduce(content) { |acc, step| step.call(acc, ctx) }
      end

      def process(content : String, resolved : Resolved, ctx : Context) : Bytes
        process(content.to_slice, resolved, ctx)
      end
    end

    struct Resolved
      getter source_name : String
      getter base : String
      getter output_name : String
      getter format : String?
      getter steps : Array(Step)

      def initialize(@source_name, @base, @output_name, @format, @steps)
      end

      def passthrough? : Bool
        @steps.empty?
      end

      def processed? : Bool
        !passthrough?
      end
    end
  end
end
