# ssg

A small static site generator in Crystal. Content is Markdown, templates are
[Crinja](https://github.com/straight-shoota/crinja) (Jinja2), and output
formats are derived from filename extension chains rather than configured.

## Usage

    ssg init DIR                               # a minimal site that builds
    ssg build [-s DIR] [-b URL] [--drafts] [--clean] [--touch]
    ssg serve [-s DIR] [-p PORT] [-b URL] [--drafts]   # rebuilds and reloads the browser on change
    ssg orphans [-s DIR] [-0]
    ssg hugo-convert [-w] FILE...

`-b URL` overrides `base_url` for one build; `serve` defaults it to the
local address.

`ssg orphans` prints every file in the output directory that the current
site would not produce, one absolute path per line, or NUL-terminated
with `-0`. The set of output paths is computed from the site graph, so
nothing is rendered or written:

    ssg orphans -0 | xargs -0 rm --

A build rewrites only output files whose content changed, so unchanged
files keep their mtime. `--touch` gives unchanged files a fresh mtime as
well, for the same purpose with plain shell tools:

    touch .stamp && ssg build --touch && find public -type f ! -newer .stamp

A site is a directory with `config.yml`, `content/`, `layouts/` and
optionally `static/` and `data/`. Output goes to `public/`.

    title: My Site
    base_url: https://example.com/
    taxonomies: [tags, categories]   # default
    paginate: 0                      # default: no pagination
    permalinks:                      # url patterns per top-level section
      blog: /:year/:month/:slug/     # :year :month :day :slug :section :title :filename
    cascade:                         # front matter defaults for every page
      author: Jane
    markdown:                        # markd options, all off by default
      smart: true                    # curly quotes and dashes
      safe: false                    # true drops raw html
      highlight: github              # theme name, or false; default default-dark
      line_numbers: false
    params:                          # free-form, available as site.params
      author: Jane

## Extension chains

A filename is `base.e1.e2...en`. Extensions are consumed from the right.
Three kinds of extension exist, and nothing else about formats is
configured anywhere:

- a **processor** is keyed by the extension it consumes. It either produces
  a fixed format (`md` produces html, `scss` produces css) or is transparent
  (`j2`: the output has whatever format the filename names next);
- a **converter** is keyed by a pair of formats, such as html -> txt or
  html -> pdf, and is applied whenever the chain needs to get from one to
  the other;
- anything else is a **format**.

Resolution, right to left: run the processors, tracking the current
format; consume the next extension if it names that format; then apply
converters as far as they reach. What remains is the base. All of this is
decided from the filename alone, so output paths are known before any file
is read, and an unreachable format is reported at scan time.

| Source               | Steps                    | Output           |
|----------------------|--------------------------|------------------|
| `test.html.j2`       | j2                       | `test.html`      |
| `post.md`            | md                       | `post.html`      |
| `post.md.j2`         | j2, then md              | `post.html`      |
| `notes.txt.md`       | md, then html -> txt     | `notes.txt`      |
| `report.pdf.html.md` | md, then html -> pdf     | `report.pdf`     |
| `report.pdf.md`      | same, intermediate implied | `report.pdf`   |
| `sitemap.xml.j2`     | j2                       | `sitemap.xml`    |
| `main.scss`          | scss                     | `main.css`       |
| `main.css.scss.j2`   | j2, then scss            | `main.css`       |
| `logo.png`           | none                     | `logo.png`       |
| `archive.tar.gz`     | none (no gz -> tar)      | `archive.tar.gz` |

Shipped: processors `md`, `j2`, `scss` and `sass` (libsass); converter
html -> txt. A pdf converter is
a class with `from = "html"`, `to = "pdf"` and a `call(Bytes, Context) :
Bytes`, registered on the registry; content is bytes end to end so binary
formats need nothing special.

Layouts follow the same rule: `layouts/page.html.j2` serves html,
`layouts/list.xml.j2` serves xml, and `page.pdf.html.j2` renders
the full html document and converts it. A page is rendered in every format
for which a layout matches its kind, so adding `list.xml.j2` turns on feeds
for every section and adding `page.pdf.html.j2` gives every page a pdf.

## Pages are directories

Every page is a directory. `content/about.md` is shorthand for
`content/about/index.md`. Both become `public/about/index.html`, served at
`/about/`.

Inside a page directory:

- `index.*` files are the page's output variants (`index.md` and
  `index.xml.j2` are the same page in two formats).
- every other file, and every subdirectory that is not itself a page, is a
  *resource*, emitted into the page's output directory under the same
  relative path. So `![x](./img/x.png)` in the Markdown just works.
- a subdirectory with an `index.*` file is a child page.

A directory with no index file is an implicit section if any page lives
below it (a list page is synthesized), and a resource directory of the
nearest ancestor page otherwise.

Resources go through the extension chain too: `content/sitemap.xml.j2` is a
resource of the home page, rendered with `site` and `page` in scope and
written to `public/sitemap.xml`.

## Front matter

YAML between `---` lines. Reserved keys: `title`, `date`, `draft`,
`weight`, `slug`, `url`, `aliases`, `layout`, `paginate`, `outputs`,
`cascade`, plus one key per taxonomy (`tags`, ...). Everything else is reachable as
`page.params.key` or simply `page.key`.

## URLs

A page's url is, in order: `url` from front matter; the `permalinks`
pattern for its top-level section (regular pages only); else its parent's
url plus its own `slug` (default: the directory name). A `url` with a file
extension, such as `/404.html`, names a single output file of that format
and nothing else is produced for the page. `aliases` lists old
urls, each of which becomes a small redirect page pointing here;
`layouts/alias.html.j2` replaces the built-in one and receives `page` (the
target) and `alias`. Resources always move with their page.

`cascade:` in `config.yml` or in a page's front matter supplies default
front matter to that page and everything below it. The nearest value wins,
and a page's own keys always win. Synthesized pages (implicit sections,
taxonomy indexes and terms) take cascaded values like any other page,
which is how they are configured at all.

## Choosing outputs

`outputs:` lists the formats a page is rendered in. Without it a page gets
every format one of its files provides plus every format a layout matches;
`outputs` only ever narrows that set. `outputs: [html]` keeps the page out
of feeds, and `outputs: []` writes nothing for the page while it stays in
the site graph, so it is still listed, paginated and linked by `next` and
`prev`. Resources and aliases are unaffected.

Combined with `cascade` this switches auto-generated pages off:

    # config.yml: no feeds anywhere, nothing at /tags/ or /tags/foo/
    cascade:
      outputs: [html]

    # content/tags/index.md: keep the term pages, hide the index itself
    ---
    outputs: []
    ---

    # content/docs/index.md: no pdf for this section and its children
    ---
    cascade:
      outputs: [html, xml]
    ---

For a taxonomy nobody should see at all, dropping it from `taxonomies` in
`config.yml` is simpler: no pages are created and no terms are indexed.

## Code highlighting

Fenced code blocks are highlighted at build time (Tartrazine, Chroma's
lexers and themes). Output uses css classes, so emit the theme's stylesheet
once, for example as `content/css/highlight.css.j2` containing
`{{ highlight_css() }}`. Unknown languages render as plain code.

## Page kinds and layout lookup

A page is either a `page` or a `list`. The home page, sections, taxonomy
indexes (`/tags/`) and terms (`/tags/foo/`) are all lists; `page.pages` is
what they list, and `page.taxonomy` / `page.term` say why.

For a page of kind `K`, top-level section `S` and format `F`, the first
existing layout wins, trying names in this order and each name first in
`layouts/S/` and then in `layouts/`:

1. `<layout>` when front matter sets `layout`
2. `home` for the home page
3. `K`

So `layouts/page.html.j2` and `layouts/list.html.j2` are all a site needs,
`layouts/blog/page.html.j2` overrides posts, and `layouts/tags/list.html.j2`
covers both `/tags/` and every term under it.

Layouts are full Crinja templates, so `{% extends %}`, `{% include %}` and
`{% import %}` work relative to `layouts/`. The page body is in `content`.

## Pagination

Set `paginate: N` in a list page's front matter, or `paginate` in
`config.yml` for all lists. The html output of the list is then rendered
once per slice of `page.pages`: `/blog/`, `/blog/page/2/`, and so on. Every
list layout gets a `paginator` with `pages`, `number`, `total`, `url`,
`prev_url`, `next_url`, `urls`, `first` and `last`; unpaginated lists get
one with all pages and a total of 1, so templates always iterate
`paginator.pages`. Other formats (feeds) are never paginated.

## Template variables

`site`: `title`, `base_url`, `params`, `home`, `pages`, `regular_pages`,
`sections`, `taxonomies`, `page(path)`.

`page`: `title`, `date`, `url`, `permalink`, `kind`, `section`, `content`,
`summary`, `params`, `parent`, `children`, `pages`, `regular_pages`, `next`,
`prev`, `resources`, `resource(path)`, `terms_for(taxonomy)`, `taxonomy`,
`term`, `headings`, `links`, `outputs`, `store`.

`page.summary` is the `summary` front matter key, else `description`, else
the first paragraph of the content. `page.plain` is the text of the
content with tags removed, for search indexes. `page.links` lists every link in the
rendered content, unique by url, each with `url`, `text` and `external`.

`site.data`: contents of the data directory. `site.page(ref)` finds a
page by content path, or by slug or directory name when given a bare name.

Extra filters: `date(format)`, `markdown`, `absurl`, `slugify`, `json`
(plain JSON, unlike Crinja's html-escaping `tojson`).
Extra functions: `ref(content_path)`.

## Static files and Sass

`static/` is copied to the output root, but every file goes through the
extension chain first, so `static/css/main.scss` becomes `css/main.css`
and a `.j2` file there is rendered with `site` in scope. Files and
directories whose name starts with `_` are private (Sass partials) and
are never output. `@import` looks next to the importing file first, then
in every static directory, site before themes, so a site can override a
theme's partial. `sass: {style: compressed}` in `config.yml` picks the
output style (nested, expanded, compact, compressed).

## Themes

    theme: minima            # or a list, highest priority first

A theme is a directory `themes/<name>/` with its own `layouts/`, `static/`
and `data/`. `themes/minima/` in this repository is a complete one, ported
from Hugo, with its own README and example site. Lookups go to the site's directory first, then to each theme
in order: a layout, static file, data file or shortcode macro in the site
overrides the theme's copy of the same path or name, and `{% extends %}`
and `{% include %}` resolve the same way. Everything else about a theme is
convention: layouts should iterate `site.sections` and `page.pages`
rather than naming sections, and theme settings belong under
`site.params`.

## Shortcodes

Shortcodes are ordinary Jinja macros in `layouts/shortcodes.j2`. Every
macro defined there is imported once into the template environment, so
templates and content can call them directly:

    {% macro L(url, title=none) %}<a href="{{ url }}">{{ title | default(url, true) }}</a>{% endmacro %}
    {% macro bq(cite=none) %}<blockquote>{{ caller() }}</blockquote>{% endmacro %}

    {{ L("https://example.org", "Example") }}
    {% call bq(cite="me") %}
    Some lines.
    {% endcall %}

Macros see `page` and `site`. Two Crinja quirks to know: `a or b` yields a
boolean, so use `a | default(b, true)` for fallbacks; and there is no inline
`x if c else y`, so use `{% if %}` blocks.

For anything a shortcode needs to hand to the layout, there is a per-page
store: `page.store.set(key, value)`, `page.store.append(key, value)`,
`page.store.get(key)`. Content renders before layouts, so the layout sees
what the content wrote. Links and headings need no store: `page.links` and
`page.headings` are extracted from the rendered html.

`ssg hugo-convert FILE...` translates Hugo's `{{< name args >}}` and
paired `{{< name >}}...{{< /name >}}` calls into the above, once, for
existing content. With `-w` it replaces each `x.md` by the converted
`x.md.j2`.

## Data files

`data/*.yml`, `*.yaml` and `*.json` are loaded into `site.data`, nested by
directory: `data/series.yml` is `site.data.series`.

## Headings

The Markdown processor gives every heading an `id` derived from its text,
unique within the page. `page.headings` lists them in order with `level`,
`id` and `text`, which is all a table of contents needs.

## Sorting

Sibling pages sort by `weight` ascending (unweighted last), then `date`
descending, then title. In templates, `sort(attribute=...)` puts pages that
lack the attribute last instead of failing.

## Building

    shards install
    shards build

Native libraries: libyaml, libxml2, openssl and libsass (`libsass-dev`).
If your system lacks the unversioned `.so` symlinks, install the `-dev`
packages, or point the linker at local symlinks:

    crystal build src/main.cr -o bin/ssg --link-flags "-L$PWD/.link"

Tests: `crystal spec`.
