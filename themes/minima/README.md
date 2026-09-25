# Minima for ssg

A port of the [Minima](https://github.com/mivinci/hugo-theme-minima) Hugo
theme (crystallabs fork). Clean, minimal, with light/dark/sand/rock colour
schemes, build-time code highlighting, series and tags, RSS, a client-side
search, a table of contents, an automatic list of external links, and
optional KaTeX, Mermaid and comment widgets.

Use it from a site's `config.yml`:

    theme: minima
    themes_dir: ../themes      # wherever this directory lives
    taxonomies: [tags, series]

`exampleSite/` is a complete site using the theme; build it with
`ssg build -s themes/minima/exampleSite`.

## Layout

    layouts/
      base.html.j2       document shell: head, header, footer
      home.html.j2       greeting, author, posts grouped by series
      page.html.j2       an article
      list.html.j2       sections, taxonomy indexes and terms
      search.html.j2     for a page with `layout: search`
      404.html.j2        for a page with `layout: "404"` and `url: /404.html`
      list.xml.j2        RSS for the home page, sections and terms
      home.json.j2       search index
      shortcodes.j2      macros: L, R, bq, series, tags, terms
      partials/          item, series box, links box, toc, plugins
    static/css/             minima.css.scss plus _partials, compiled by the tool
    static/js/              minima.js (scheme switch), search.js, fuse
    data/icons.yml          inline svg icons for params.social

## Params

    params:
      brand: Minima                 # header text, optional
      greet: "Hello :)"             # home page heading
      subtitle:                     # appended to the home page <title>
      author:
        status: Currently on Earth
        description: Markdown shown on the home page
      copyright: "© 2026 Someone"
      menu:                         # header links
        - {name: Tags, url: /tags/}
        - {name: Series, url: /series/}
      social:                       # footer icons, names from data/icons.yml
        - {name: github, url: https://github.com/x}
        - {name: rss, url: /index.xml}
      switch: ["🌚", "🌝"]           # scheme toggle icons
      default_theme: light          # light | dark | sand | rock | system
      display_date: true
      display_description: true
      selectable: true              # false disables text selection
      toc: false                    # default for pages; `toc: true` in front matter overrides
      rss_limit: 20
      search: {title: Search, placeholder: Enter keywords, fuse: {keys: [title, summary, content], threshold: 0.4}}
      math: {enable: false}         # KaTeX; `math: true` in front matter overrides
      diagram: {enable: false}      # Mermaid, for ```mermaid blocks
      comment: {enable: false, provider: giscus, giscus: {repo:, repo_id:, category:, category_id:}}
                                    # providers: giscus, utterances {repo:}, disqus {shortname:}

Descriptions for series and tags come from `data/series.yml` and
`data/tags.yml`, keyed by term.

## Front matter

`title`, `date`, `lastmod`, `description`, `tags`, `series`, `weight`
(order within a series), `draft`, `toc`, `math`, `diagram`, `comment`,
`banner` (image url), `link` (list entries point there instead).

## Differences from the Hugo theme

Left out: i18n and multilingual mode, Google Analytics and OpenGraph
tags, the JS bundler and asset fingerprinting, and the "friends" feed.
The stylesheet is SCSS compiled at build time, generating only the
utility classes the layouts use. Links are collected from the rendered article rather than
recorded by a shortcode, so plain Markdown links count too. Highlighting
uses the tool's build-time highlighter, coloured through the same scheme
variables as before.
