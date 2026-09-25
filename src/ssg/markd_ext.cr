require "markd"
require "tartrazine"

# markd highlights fenced code through Tartrazine whenever Tartrazine is
# loaded, and raises on unknown languages. Make both configurable: a nil
# formatter renders plain <pre><code>, and an unknown language falls back to
# plain text rather than failing the build.
class Markd::HTMLRenderer
  private def render_code_block_use_tartrazine(node : Node, formatter : Tartrazine::Formatter?)
    languages = node.fence_language ? node.fence_language.split : nil
    lang = code_block_language(languages)
    newline

    lexer = if lang && formatter
              begin
                Tartrazine.lexer(lang)
              rescue Tartrazine::UnknownLexerError
                nil
              end
            end

    if lexer && formatter
      literal(formatter.format(node.text.chomp, lexer))
    else
      # Same markup as markd without Tartrazine, language class included.
      code_tag_attrs = attrs(node)
      if lang
        code_tag_attrs ||= {} of String => String
        code_tag_attrs["class"] = "language-#{escape(lang)}"
      end
      pre_tag_attrs = @options.prettyprint? ? {"class" => "prettyprint"} : nil
      tag("pre", pre_tag_attrs) do
        tag("code", code_tag_attrs) do
          code_block_body(node, lang)
        end
      end
      newline
    end
  end
end
