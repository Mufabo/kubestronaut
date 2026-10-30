-- Pandoc filter for the EPUB (tools/build-epub.sh).
--
-- 1. Mermaid code blocks become PNG images, rendered with mermaid-cli (mmdc).
--    MERMAID_OUT is the folder for the images; MMDC is the command to run (for
--    example "npx -y @mermaid-js/mermaid-cli@VERSION"); MMDC_PUPPETEER_CONFIG
--    is passed to it with -p. If a diagram cannot be rendered, its source stays.
-- 2. Links to files of the repository (lab/solutions.md, ../04-pods/...) lead
--    nowhere inside an EPUB, so they become their plain text. Web links and
--    links within the book stay.

local outdir = os.getenv("MERMAID_OUT") or "build/mermaid"
local mmdc = os.getenv("MMDC") or "mmdc"
local puppeteer = os.getenv("MMDC_PUPPETEER_CONFIG")
local count = 0

function CodeBlock(el)
  if not el.classes:includes("mermaid") then
    return nil
  end
  count = count + 1
  local base = string.format("%s/diagram-%03d", outdir, count)
  local src = io.open(base .. ".mmd", "w")
  src:write(el.text)
  src:close()
  local cmd = string.format('%s -q -i "%s.mmd" -o "%s.png" -b white -s 2', mmdc, base, base)
  if puppeteer then
    cmd = cmd .. string.format(' -p "%s"', puppeteer)
  end
  if os.execute(cmd .. " >/dev/null 2>&1") then
    return pandoc.Para({ pandoc.Image({}, base .. ".png") })
  end
  io.stderr:write(string.format("warning: could not render Mermaid diagram %d; keeping its source\n", count))
  return nil
end

function Link(el)
  local target = el.target
  if target:match("^%a[%w+.-]*:") or target:match("^#") then
    return nil
  end
  return pandoc.Span(el.content)
end
