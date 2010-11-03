class OPML
  def initialize(title = nil)
    @doc = Document.new
    @doc.xml_decl.dowrite
    @doc.add_element Element.new("opml")
    @doc.root.add_attribute "version", "1.1"
    head = Element.new("head")
    @doc.root.add_element head
    if title
      titlee = Element.new("title")
      titlee.text = title
      head.add_element titlee
    end
    @body = Element.new("body")
    @doc.root.add_element @body
    @size = 0
  end
  def add(feedurl, text=nil)
    e = Element.new("outline")
    e.add_attribute("text", text) if text
    e.add_attribute "type", "link"
    e.add_attribute "url", feedurl
    @body.add_element e
    @size += 1
  end
  def write()
    @doc.write $stdout, 0
  end
  def size()
    @size
  end
end


