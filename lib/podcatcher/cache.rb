class Cache
  def initialize(opt)
    super()
    @opt = opt
    @@TORRENT = "application/x-bittorrent"
    @@MEDIA_RSS_NS = ['http://search.yahoo.com/mrss/']
    @@MEDIA_RSS_NS << 'http://search.yahoo.com/mrss'
    @@ATOM_NS = Regexp.new "^http://purl.org/atom/ns#"
    #history
    @history = History.new opt.dir
    #stats
    @stats = Stats.new opt.dir
    #cache
    @cache_dir = opt.cachedir #opt.dir+"cache"
    @cache_dir.mkdir() unless @cache_dir.exist?
    exit 1 unless @cache_dir.directory?
    @cache_dir.each_entry() do |e|
      e = @cache_dir+e
      e = e.cleanpath
      next if e == @cache_dir or e == @cache_dir.parent
      if e.directory? #feed subfolder
        e.each_entry() do |e2|
          e2 = e+e2
          next if e2.directory?
          if opt.empty
            unless opt.simulate or opt.strategy == :cache
              $stderr.puts "Deleting: #{e2}" if opt.verbose
              e2.delete
            end
          end
        end
        e.delete if e.entries.size == 2
      elsif opt.empty
        unless opt.simulate or opt.strategy == :cache
          $stderr.puts "Deleting: #{e}" if opt.verbose
          e.delete
        end
      end
    end
    @cache = @cache_dir.entries.collect() do |e|
      e = @cache_dir+e
      e = e.cleanpath
      next if e == @cache_dir or e == @cache_dir.parent
      if e.file?
        content = OpenStruct.new
        content.file = e
        content.size = e.size
        content.title = e.to_s
        content
      elsif e.directory?
        e.entries.collect() do |e2|
          e2 = e+e2
          if e2.file?
            content = OpenStruct.new
            content.file = e2
            content.size = e2.size
            content.title = e2.to_s
            content
          else
            nil
          end
        end
      else
        nil
      end
    end
    @cache.flatten!
    @cache.compact!
    @cache.sort!() do |e,e2|
      e.file.mtime() <=> e2.file.mtime()
    end
  end
  def createplaylist(urls)
    playlist = Playlist.new @opt.playlist_type
    if @opt.strategy == :cache
      playlist.start
      @cache.reverse!
      @cache.each() do |content|
        playlist.add content
      end
      playlist.finish
      return playlist.to_s
    end
    playlist.start
    doc = nil
    if urls.size == 0
      $stderr.puts "Reading document from standard input" if @opt.verbose
      begin
        xml = ""
        $stdin.each() do |e|
          xml += e
        end
        doc = OpenStruct.new
        doc.dom = Document.new(xml)
        doc = nil unless doc.dom
      rescue Interrupt, SystemExit
        exit 1
      rescue Exception
        $stderr.puts "Error: unreadable document"
        doc = nil
      end
    end
    dochistory = []
    feeds = []
    urls.uniq!
    links = urls.collect() do |e|
      l = OpenStruct.new
      l.url = e
      l
    end
    loop do
      break if @opt.feeds and feeds.size >= @opt.feeds
      while not doc
        link = links.shift
        break unless link
        if dochistory.detect{|e| e == link.url}
          $stderr.puts "Skipping duplicate: #{link.url}" if @opt.verbose
          next
        end
        $stderr.puts "Fetching: #{link.url}" if @opt.verbose
        dochistory << link.url
        begin
          doc = fetchdoc(link)
        rescue Interrupt, SystemExit
          exit 1
        rescue Exception
          $stderr.puts "Error: skipping unreadable document"
        end
      end
      break unless doc
      begin
        if doc.dom.root.name == "opml"
          newlinks = []
          outlines = []
          doc.dom.elements.each("/opml/body") do |body|
            body.elements.each() do |e|
              next unless e.name == 'outline'
              outlines << e
            end
          end
          while outlines.size>0
            outline = outlines.shift
            url = outline.attributes["xmlUrl"]
            url = outline.attributes["url"] unless url
            if url
              begin
                url = URI.parse(doc.url).merge(url).to_s if doc.url
                link = OpenStruct.new
                link.url = url
                link.referrer = doc.url
                newlinks << link
              rescue URI::InvalidURIError
              end
              next
            end
            new_outlines = []
            outline.elements.each() do |e|
              next unless e.name == 'outline'
              new_outlines << e
            end
            outlines = new_outlines + outlines
          end
          links = newlinks + links
        elsif doc.dom.root.name == "pcast"
          newlinks = []
          XPath.each(doc.dom,"//link[@rel='feed']") do |outline|
            url = outline.attributes["href"]
            next unless url
            begin
              url = URI.parse(doc.url).merge(url).to_s if doc.url
              link = OpenStruct.new
              link.url = url
              link.referrer = doc.url
              newlinks << link
            rescue URI::InvalidURIError
            end
          end
          links = newlinks + links
        elsif doc.dom.root.namespace =~ @@ATOM_NS
          feed = []
          XPath.each(doc.dom.root,"//*[@rel='enclosure']") do |e2|
            next unless e2.namespace =~ @@ATOM_NS
            content = OpenStruct.new
            XPath.each(e2,"parent::/title/text()") do |node|
              content.title = ""
              node.value.each() do |e3| #remove line breaks
                content.title+= e3.chomp+" "
              end
              content.title.strip!
            end
            XPath.each(e2,"parent::/created/text()") do |node|
              pub_date = ""
              node.value.each() do |e3| #remove line breaks
                pub_date+= e3.chomp+" "
              end
              begin
                content.pub_date = DateTime.parse(pub_date.strip, true)
              rescue Exception
              end
            end
            content.mime = e2.attributes["type"].downcase
            next if @opt.content_type !~ content.mime and content.mime != @@TORRENT
            next if content.mime == @@TORRENT and not (@opt.torrent_dir or @opt.rubytorrent)
            content.feedurl = doc.url
            begin
              content.url = URI.parse(content.feedurl).merge(e2.attributes["href"]).to_s if content.feedurl
              content.size = e2.attributes["length"].to_i
              content.size = 2 unless content.size and content.size>0
              content.size = 0 if content.mime == @@TORRENT #not strictly necessary
              feed << content
            rescue URI::InvalidURIError
            end
          end
          #sort by date
          feed.sort!() do |a,b|
            if a.pub_date
              if b.pub_date
                b.pub_date <=> a.pub_date
              else
                -1
              end
            else
              if b.pub_date
                1
              else
                0
              end
            end
          end
          feed.each() do |content|
            $stderr.puts "Enclosure: #{content.url}"
          end if @opt.verbose
          #title
          node = XPath.first(doc.dom,"/feed/title/text()")
          feed_title = ""
          node.value.each() do |e3| #remove line breaks
            feed_title += e3.chomp+" "
          end
          feed_title.strip!
          feed.each() do |content|
            content.feed_title = feed_title
          end
          #
          feeds << feed
        elsif doc.dom.root.name = "rss"
          feed = []
          doc.dom.root.elements.each() do |e| #channel
            e.elements.each() do |e1| #item
              title = ''
              XPath.each(e1,"title/text()") do |node|
                title = ''
                node.value.each() do |e3| #remove line breaks
                  title+= e3.chomp+" "
                end
                title.strip!
              end
              pub_date = nil
              XPath.each(e1,"pubDate/text()") do |node|
                pub_date = ""
                node.value.each() do |e3| #remove line breaks
                  pub_date+= e3.chomp+" "
                end
                begin
                  pub_date = DateTime.parse(pub_date.strip, true)
                rescue Exception
                  pub_date = nil
                end
              end
              e1.elements.each() do |e2|
                if e2.name == "enclosure"
                  content = OpenStruct.new
                  content.title = title
                  content.pub_date = pub_date
                  content.mime = e2.attributes["type"].downcase
                  next if @opt.content_type !~ content.mime and content.mime != @@TORRENT
                  next if content.mime == @@TORRENT and not (@opt.torrent_dir or @opt.rubytorrent)
                  content.feedurl = doc.url
                  begin
                    content.url = URI.parse(content.feedurl).merge(e2.attributes["url"]).to_s if content.feedurl
                    content.size = e2.attributes["length"].to_i
                    content.size = 2 unless content.size and content.size>0
                    content.size = 0 if content.mime == @@TORRENT #not strictly necessary
                    feed << content
                  rescue URI::InvalidURIError
                  end
                elsif @@MEDIA_RSS_NS.include? e2.namespace
                  case e2.name
                  when 'content'
                    content = OpenStruct.new
                    content.title = title
                    content.pub_date = pub_date
                    content.mime = e2.attributes["type"].downcase
                    next if @opt.content_type !~ content.mime and content.mime != @@TORRENT
                    next if content.mime == @@TORRENT and not (@opt.torrent_dir or @opt.rubytorrent)
                    content.feedurl = doc.url
                    begin
                      content.url = URI.parse(content.feedurl).merge(e2.attributes["url"]).to_s if content.feedurl
                      content.size = e2.attributes["fileSize"].to_i
                      content.size = 2 unless content.size and content.size>0
                      content.size = 0 if content.mime == @@TORRENT #not strictly necessary
                      feed << content
                    rescue URI::InvalidURIError
                    end
                  when 'group'
                    e2.elements.each() do |e4|
                      if e4.name == 'content' and @@MEDIA_RSS_NS.include?(e4.namespace)
                        content = OpenStruct.new
                        content.title = title
                        content.pub_date = pub_date
                        content.mime = e4.attributes["type"].downcase
                        next if @opt.content_type !~ content.mime and content.mime != @@TORRENT
                        next if content.mime == @@TORRENT and not (@opt.torrent_dir or @opt.rubytorrent)
                        content.feedurl = doc.url
                        begin
                          content.url = URI.parse(content.feedurl).merge(e4.attributes["url"]).to_s if content.feedurl
                          content.size = e4.attributes["fileSize"].to_i
                          content.size = 2 unless content.size and content.size>0
                          content.size = 0 if content.mime == @@TORRENT #not strictly necessary
                          feed << content
                        rescue URI::InvalidURIError
                        end
                        break
                      end
                    end
                  end

                end
              end if e1.name == "item"
            end if e.name == "channel"
          end
          #remove duplicates (duplication occurs in particular for content declared as both enclosure and Media RSS content)
          for i in 0...feed.size
            content = feed[i]
            next unless content
            for j in i+1...feed.size
              next unless feed[j]
              feed[j] = nil if feed[j].url == content.url
            end
          end
          feed.compact!
          #sort by date
          feed.sort!() do |a,b|
            if a.pub_date
              if b.pub_date
                b.pub_date <=> a.pub_date
              else
                -1
              end
            else
              if b.pub_date
                1
              else
                0
              end
            end
          end
          feed.each() do |content|
            $stderr.puts "Enclosure: #{content.url}"
          end if @opt.verbose
          #title
          node = XPath.first(doc.dom,"//channel/title/text()")
          feed_title = ""
          node.value.each() do |e3| #remove line breaks
            feed_title += e3.chomp+" "
          end
          feed_title.strip!
          feed.each() do |content|
            content.feed_title = feed_title
          end
          #language
          if @opt.language.size > 0
            loop do
              node = XPath.first doc.dom, '//channel/language/text()'
              break unless node
              break unless node.value
              feed_lang = node.value.strip.downcase.split '-'
              break if feed_lang.size == 0
              langmatch = @opt.language.collect() do |lang|
                next false if feed_lang.size < lang.size
                matches = true
                for i in 0...lang.size
                  next if lang[i] == feed_lang[i]
                  matches = false
                end
                matches
              end
              feeds << feed if langmatch.include? true
              break
            end
          else
            feeds << feed
          end
        end
      rescue Interrupt, SystemExit
        exit 1
      rescue Exception
        $stderr.puts "Error: skipping document because of an internal error"
      end
      doc = nil
    end
    #remove content older than the horizon date
    if @opt.horizon
      feeds.each() do |feed|
        for i in 0...feed.size
          if feed[i].pub_date
            feed[i] = nil if feed[i].pub_date < @opt.horizon
          else
            feed[i] = nil
          end
        end
        feed.compact!
      end
    end
    #apply download strategy
    @history.mark_old_content feeds
    if @opt.strategy == :chron or @opt.strategy == :chron_one or @opt.strategy == :chron_all
      feeds.each() do |feed|
        feed.reverse!
      end
      @opt.strategy = :back_catalog if @opt.strategy == :chron
      @opt.strategy = :one if @opt.strategy == :chron_one
      @opt.strategy = :all if @opt.strategy == :chron_all
    end
    case @opt.strategy #remove ignored content
    when :new
      feeds.each() do |feed|
        in_hist = nil
        for i in 0...feed.size
          if feed[i].in_history
            in_hist = i
            break
          end
        end
        feed.slice! in_hist...feed.size if in_hist
      end
    when :all
    else
      feeds.each() do |feed|
        for i in 0...feed.size
          feed[i] = nil if feed[i].in_history
        end
        feed.compact!
      end
    end
    if @opt.strategy == :new or @opt.strategy == :one
      feeds.each() do |feed|
        itemsize = 0
        index = nil
        for i in 0...feed.size
          itemsize += feed[i].size
          if itemsize >= @opt.itemsize
            index = i+1
            break
          end
        end
        feed.slice! index...feed.size if index
      end
    end
    #feed order
    case @opt.order
    when :random
      srand
      feeds.sort!() do |a,b|
        if a.size>0
          if b.size>0
            rand(3)-1
          else
            -1
          end
        else
          if b.size>0
            1
          else
            0
          end
        end
      end
    when :alphabetical
      feeds.sort!() do |a,b|
        if a.size>0
          if b.size>0
            a[0].feed_title <=> b[0].feed_title
          else
            -1
          end
        else
          if b.size>0
            1
          else
            0
          end
        end
      end
    when :reverse
      feeds.reverse!
    end
    #remove duplicate content
    feeds.each() do |feed|
      feed.each() do |content|
        next unless content
        dup = false
        feeds.each() do |f|
          for i in 0...f.size
            next unless f[i]
            if f[i].url == content.url
              f[i] = nil if dup
              dup = true
            end
            $stderr.puts "Removed duplicate: #{content.url}" unless f[i] or (not @opt.verbose)
          end
        end
      end
      feed.compact!
    end
    #send usage statistics
    @stats.ping @opt, feeds
    #fetch torrent metainfo files
    feeds.each() do |feed|
      feed.each() do |content|
        next if content.mime != @@TORRENT
        content.mime = nil
        begin
          $stderr.puts "Fetching torrent metainfo: #{content.url}" if @opt.verbose
          content.metainfo = RubyTorrent::MetaInfo.from_location content.url
          content.size = content.metainfo.info.length
          content.mime = case content.metainfo.info.name.downcase
            when /\.mp3$/
              "audio/mpeg"
            when /\.wma$/
              "audio/x-ms-wma"
            when /\.mpg$|\.mpeg$|\.mpe$|\.mpa$|\.mp2$|\.mpv2$/
              "video/mpeg"
            when /\.mov$|\.qt$/
              "video/quicktime"
            when /\.avi$/
              "video/x-msvideo"
            when /\.wmv$/
              "video/x-ms-wmv"
            when /\.asf$/
              "video/x-ms-asf"
            when /\.m4v$|\.mp4$|\.mpg4$/
              "video/mp4"
            else
              nil
            end
          content.url = nil unless content.mime
          content.url = nil unless (@opt.content_type =~ content.mime)
          content.url = nil unless content.metainfo.info.single?
        rescue Interrupt
          content.url = nil
          $stderr.puts "Error: unreadable torrent metainfo" if @opt.verbose
        rescue SystemExit
          exit 1
        rescue Exception
          content.url = nil
          $stderr.puts "Error: unreadable torrent metainfo" if @opt.verbose
        end
      end
      for i in 0...feed.size
        feed[i] = nil unless feed[i].url
      end
      feed.compact!
    end
    #fetch enclosures
    item = total = 0
    if @opt.empty
      @cache.each() do |e|
        total+= e.size
      end
    end
    torrents = []
    torrentfiles = []
    inc = 1
    while inc>0
      inc = 0
      itemsize = 0
      feeds.each do |e|
        #find next enclosure in feed
        content = e.shift
        unless content
          itemsize = 0
          next
        end
        #make place in cache
        while @opt.size and content.size+inc+total > @opt.size
          break if @opt.simulate
          break unless @opt.empty
          f = @cache.shift
          break unless f
          total-= f.size
          parent = f.file.parent
          $stderr.puts "Deleting: #{f.file}" if @opt.verbose
          f.file.delete
          if parent.parent != @opt.dir and parent.entries.size == 2
            #delete empty feed subfolder
            $stderr.puts "Deleting: #{parent}" if @opt.verbose
            parent.delete
          end
        end
        unless @opt.simulate
          break if @opt.size and content.size+inc+total > @opt.size
        end
        #download
        1.upto(@opt.retries) do |i|
          begin
            if content.metainfo
              if @opt.torrent_dir
                loop do
                  content.file = @opt.torrent_dir+(Time.now.to_f.to_s+".torrent")
                  break unless content.file.exist?
                  sleep 1
                end
                $stderr.puts "Copying: #{content.url} to #{content.file}" if @opt.verbose and i == 1
                if not @opt.simulate
                  if content.feedurl and (content.feedurl =~ %r{^http:} or content.feedurl =~ %r{^ftp:})
                    open(content.url, "User-Agent" => USER_AGENT, "Referer" => content.feedurl) do |fin|
                      content.file.open("wb") do |fout|
                        fin.each_byte() do |b|
                          fout.putc b
                        end
                      end
                    end
                  else
                    open(content.url, "User-Agent" => USER_AGENT) do |fin|
                      content.file.open("wb") do |fout|
                        fin.each_byte() do |b|
                          fout.putc b
                        end
                      end
                    end
                  end
                end
              else
                $stderr.puts "Fetching in background: #{content.url}" if @opt.verbose and i == 1
                unless @opt.simulate
                  content.file = filename(content, @cache_dir)
                  package = RubyTorrent::Package.new content.metainfo, content.file.to_s
                  bt = RubyTorrent::BitTorrent.new content.metainfo, package, :dlratelim => nil, :ulratelim => @opt.upload_rate, :http_proxy => ENV["http_proxy"]
                  torrents << bt
                  torrentfiles << content
                end
                inc+= content.size
                itemsize+= content.size
              end
            else
              $stderr.puts "Fetching: #{content.url} (#{content.size.to_s} bytes)" if @opt.verbose and i == 1
              if not @opt.simulate
                headers = {"User-Agent" => USER_AGENT}
                headers["Referer"] = content.feedurl if content.feedurl and (content.feedurl =~ %r{^http:} or content.feedurl =~ %r{^ftp:})
                content.download_url = content.url unless content.download_url
                open(content.download_url, headers) do |fin|
                  if fin.base_uri.instance_of?(URI::HTTP)
                    if fin.status[0] =~ Regexp.new('^3')
                      content.download_url = fin.meta['location']
                      raise "redirecting"
                    elsif fin.status[0] !~ Regexp.new('^2')
                      raise 'failed'
                    end
                  end
                  # write content to cache
                  content.redirection_url = fin.base_uri.to_s # content.redirection_url is used for finding the correct filename in case of redirection
                  content.redirection_url = nil if content.redirection_url.eql?(content.url)
                  content.file = filename(content, @cache_dir)
                  content.file.open("wb") do |fout|
                    fin.each_byte() do |b|
                      fout.putc b
                    end
                  end
                end
                content.size = content.file.size
                @history.add content
              end
              playlist.add(content)
              inc+= content.size
              itemsize+= content.size
            end
            break
          rescue Interrupt
          rescue SystemExit
            exit 1
          rescue Exception
          end
          $stderr.puts "Attempt #{i} aborted" if @opt.verbose
          if content.file and i == @opt.retries
            if content.file.exist?
              parent = content.file.parent
              content.file.delete
              if parent.parent != @opt.dir and parent.entries.size == 2
                #delete empty feed subfolder
                parent.delete
              end
            end
            content.file = nil
          end
          sleep 5
        end
        redo unless content.file # skip unavailable enclosures
        redo if @opt.itemsize > itemsize
        itemsize = 0
      end
      total+=inc
    end
    #shut down torrents
    if torrents.length > 0
      $stderr.puts "Fetching torrents (duration: 30min to a couple of hours) " if @opt.verbose
      bt = torrents[0]
      completion = torrents.collect() do |e|
        e.percent_completed
      end
      while torrents.length > 0
        sleep 30*60
        for i in 0...torrents.length
          c = torrents[i].percent_completed
          complete = torrents[i].complete?
          $stderr.puts "Fetched: #{c}% of #{torrentfiles[i].url} " if @opt.verbose
          if complete or c == completion[i]
            begin
              torrents[i].shutdown
            rescue SystemExit
              exit 1
            rescue Interrupt, Exception
            end
            if complete
              playlist.add(torrentfiles[i])
              @history.add torrentfiles[i]
            else
              $stderr.puts "Aborted: #{torrentfiles[i].url}" if @opt.verbose
              begin
                torrentfiles[i].file.delete if torrentfiles[i].file.exist?
                torrentfiles[i] = nil
              rescue Interrupt, SystemExit
                exit 1
              rescue Exception
              end
            end
            torrents[i] = nil
            torrentfiles[i] = nil
            completion[i] = nil
            next
          end
          completion[i] = c
        end
        torrents.compact!
        torrentfiles.compact!
        completion.compact!
      end
      begin
        bt.shutdown_all
      rescue Interrupt, SystemExit
        exit 1
      rescue Exception
      end
      $stderr.puts "BitTorrent stopped" if @opt.verbose
    end
    playlist.finish
    @history.trim(@opt.memsize) unless @opt.simulate or @opt.strategy == :cache
    playlist.to_s
  end
private
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
        exit 1
      rescue Exception
      end
      $stderr.puts "Attempt #{i} aborted" if @opt.verbose
      doc = ""
      sleep 5
    end
    res = OpenStruct.new
    begin
      res.dom = Document.new doc
    rescue Exception
    end
    if res.dom
      res.url = link.url
    else
      res = nil
    end
    res
  end
  def filename(content, dir) #produce filename for content to be downloaded
    begin #per-feed subfolder
      if @opt.per_feed and content.feed_title and content.feed_title.size > 0
        newdir = dir+content.feed_title
        newdir = dir+content.feed_title.gsub(/[\\\/:*?\"<>|!]/, ' ').gsub(/-+/,'-').gsub(/\s+/,' ').strip if @opt.restricted_names
        if newdir.exist?
          if newdir.directory?
            dir = newdir
          end
        else
          newdir.mkdir
          dir = newdir
        end
      end
    rescue Exception
    # $stderr.puts "error: #{$!}"
    end

    if content.metainfo
      begin
        name = content.metainfo.info.name
      rescue Exception
      end
    else
      urlname = nil
      urlname = URI.split(content.redirection_url)[5].split("/")[-1] if content.redirection_url
      urlname = URI.split(content.url)[5].split("/")[-1] unless urlname
      name = URI.unescape(urlname)
    end
    orig_name = name if (dir+name).exist?

    #unique name?
    loop do
      name = "#{Time.now.to_i.to_s}.#{orig_name}"
      break unless (dir+name).exist?
      sleep 1
    end if (dir+name).exist?
    dir+name
  end
end