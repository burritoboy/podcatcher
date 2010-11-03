class Query
  def initialize(opt, query)
    @@ATOM_NS = Regexp.new '^http://purl.org/atom/ns#'
    @@ITUNES_NS = 'http://www.itunes.com/dtds/podcast-1.0.dtd'
    @opt = opt
    if query
      @query = query.downcase.split
      @query = nil if @query.size == 0
    end
    @stats = Stats.new opt.dir
  end
  def search(urls)
    res = []
    begin
      newpaths = []
      dochistory = []
      paths = []
      if urls.size == 0
        $stderr.puts "Reading subscriptions from standard input" if @opt.verbose
        begin
          xml = ""
          $stdin.each() do |e|
            xml += e
          end
          path = OpenStruct.new
          path.doc = Document.new(xml)
          if path.doc and path.doc.root
            path.relevance = 0
            newpaths << path
          end
        rescue Interrupt, SystemExit
          raise
        rescue Exception
          $stderr.puts "Error: unreadable subscriptions"
        end
      else
        newpaths = urls.uniq.collect() do |e|
          path = OpenStruct.new
          path.url = e
          path
        end
        newpaths = newpaths.collect() do |path|
          $stderr.puts "Fetching: #{path.url}" if @opt.verbose
          dochistory << path.url
          path.doc = fetchdoc(path)
          if path.doc
            path.relevance = 0
            path
          else
            $stderr.puts "Skipping unreadable document" if @opt.verbose
            nil
          end
        end
        newpaths.compact!
      end
      #send usage statistics
      @stats.ping_search @opt, @query.join(' ')
      #
      loop do
        break if @opt.feeds and res.size >= @opt.feeds
        begin
          newpaths.sort!() do |path1, path2|
            path2.relevance <=> path1.relevance
          end
          paths = newpaths + paths
          newpaths = []
          path = nil
          loop do
            path = paths.shift
            break unless path
            if path.doc
              break
            else
              if dochistory.detect{|e| e == path.url}
                $stderr.puts "Skipping duplicate: #{path.url}" if @opt.verbose
                next
              end
              $stderr.puts "Fetching: #{path.url}" if @opt.verbose
              dochistory << path.url
              path.doc = fetchdoc(path)
              if path.doc
                break
              end
              $stderr.puts "Error: skipping unreadable document"
            end
          end
          break unless path
          if path.doc.root.name == "opml"
            #doc relevance
            path.relevance += relevance_of(XPath.first(path.doc, "/opml/head/title/text()"))
            #outgoing links
            XPath.each(path.doc,"//outline") do |outline|
              url = outline.attributes["xmlUrl"]
              url = outline.attributes["url"] unless url
              next unless url
              begin
                url = URI.parse(path.url).merge(url).to_s if path.url
              rescue Interrupt, SystemExit
                raise
              rescue Exception
              end
              newpath = OpenStruct.new
              newpath.url = url
              newpath.referrer = path.url
              #link relevance
              newpath.relevance = path.relevance
              XPath.each(outline, "ancestor-or-self::outline") do |e|
                newpath.relevance += relevance_of(e.attributes["text"])
              end
              #
              newpaths << newpath
            end
          elsif path.doc.root.name == "pcast"
            #outgoing links
            XPath.each(path.doc,"/pcast/channel") do |channel|
              link = XPath.first(channel, "link[@rel='feed']")
              next unless link
              url = link.attributes["href"]
              next unless url
              begin
                url = URI.parse(path.url).merge(url).to_s if path.url
              rescue Interrupt, SystemExit
                raise
              rescue Exception
              end
              newpath = OpenStruct.new
              newpath.url = url
              newpath.referrer = path.url
              #link relevance
              newpath.relevance = path.relevance
              newpath.relevance += relevance_of(XPath.first(channel, "title/text()"))
              newpath.relevance += relevance_of(XPath.first(channel, "subtitle/text()"))
              #
              newpaths << newpath
            end
          elsif path.doc.root.namespace =~ @@ATOM_NS and path.url
            #doc relevance
            title = nil
            begin
              XPath.each(path.doc.root,"/*/*") do |e|
                next unless e.namespace =~ @@ATOM_NS
                next unless e.name == "title" or e.name == "subtitle"
                title = e.text if e.name == "title"
                path.relevance += relevance_of(e.text)
              end
            rescue Interrupt, SystemExit
              raise
            rescue Exception
              #$stderr.puts "error: #{$!}"
            end
            if path.relevance > 0
              $stderr.puts "Found: #{title} (relevance: #{path.relevance})" if @opt.verbose
              if title
                path.title = ""
                title.value.each() do |e3| #remove line breaks
                  path.title+= e3.chomp+" "
                end
                path.title.strip!
              end
              res << path
            end
          elsif path.doc.root.name = "rss" and path.url
            #doc relevance
            title = XPath.first(path.doc, "//channel/title/text()")
            path.relevance += relevance_of(title)
            path.relevance += relevance_of(XPath.first(path.doc, "//channel/description/text()"))
            begin
              XPath.each(path.doc.root,"//channel/*") do |e|
                next unless e.name == "category"
                if e.namespace == @@ITUNES_NS
                  XPath.each(e, "descendant-or-self::*") do |e2|
                    next unless e2.name == "category"
                    path.relevance += relevance_of(e2.attributes["text"])
                  end
                else
                  path.relevance += relevance_of(e.text)
                end
              end
            rescue Interrupt, SystemExit
              raise
            rescue Exception
              #$stderr.puts "error: #{$!}"
            end
            if path.relevance > 0
              $stderr.puts "Found: #{title} (relevance: #{path.relevance})" if @opt.verbose
              if title
                path.title = ""
                title.value.each() do |e3| #remove line breaks
                  path.title+= e3.chomp+" "
                end
                path.title.strip!
              end
              res << path
            end
          end
        rescue Interrupt, SystemExit
          raise
        rescue Exception
          $stderr.puts "Error: skipping unreadable document"
        end
      end
    rescue Interrupt, SystemExit
      $stderr.puts "Execution interrupted"
    rescue Exception
    end
    result = nil
    while not result
      begin
        res.sort!() do |path1, path2|
          path2.relevance <=> path1.relevance
        end
        opml = OPML.new "Search results for \"#{@query.collect(){|e| "#{e} "}}\""
        res.each() do |path|
          opml.add path.url, path.title
        end
        result = opml
      rescue Exception
      end
    end
    result.write
    result
  end
private
  def relevance_of(meta)
    return 0 unless meta
    unless meta.kind_of? String #Text todo: resolve entities
      meta = meta.value
    end
    meta = meta.downcase
    meta = meta.split
    res = 0
    @query.each() do |e|
      meta.each() do |e2|
        res += 1 if e2.index(e)
      end
    end
    res
  end
  def fetchdoc(link)
    doc = ""
    1.upto(@opt.retries) do |i|
      begin
        if link.url =~ %r{^http:} or link.url =~ %r{^ftp:}
          if link.referrer and (link.referrer =~ %r{^http:} or link.referrer =~ %r{^ftp:})
            open(link.url, "User-Agent" => USER_AGENT, "Referer" => link.referrer) do |f|
              break if f.content_type.index "audio/"
              break if f.content_type.index "video/"
              f.each_line() do |e|
                doc += e
              end
            end
          else
            open(link.url, "User-Agent" => USER_AGENT) do |f|
              break if f.content_type.index "audio/"
              break if f.content_type.index "video/"
              f.each_line() do |e|
                doc += e
              end
            end
          end
        else
          open(link.url) do |f|
            f.each_line() do |e|
              doc += e
            end
          end
        end
        break
      rescue Interrupt
      rescue SystemExit
        break
      rescue Exception
      end
      $stderr.puts "Attempt #{i} aborted" if @opt.verbose
      doc = ""
      sleep 5
    end
    res = nil
    begin
      res = Document.new doc
    rescue Exception
    end
    res = nil unless res and res.root
    res
  end
end

