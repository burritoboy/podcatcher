class Playlist
  def initialize(playlisttype)
    @playlisttype = playlisttype
    @audio_or_video = Regexp.new '^audio/|^video/'
    @size = 0
  end
  def start()
    @str = ""
    case @playlisttype
    when :tox
      @str = "# toxine playlist \n"
    when :m3u
      @str = "#EXTM3U\n"
    when :pls
      @str = "[playlist]\n"
    when :asx
      @str = <<END
<asx version = "3.0">
END
    when :smil
      @str = <<END
<?xml version="1.0"?>
<!DOCTYPE smil PUBLIC "-//W3C//DTD SMIL 2.0//EN" "http://www.w3.org/2001/SMIL20/SMIL20.dtd">
<smil xmlns="http://www.w3.org/2001/SMIL20/Language">
  <head></head>
  <body>
END
    when :xspf
      @doc = Document.new
      @doc.xml_decl.dowrite
      @doc.add_element Element.new("playlist")
      @doc.root.add_attribute "version", "1"
      @doc.root.add_attribute "xmlns", "http://xspf.org/ns/0/"
      @tracklist = Element.new("trackList")
      @doc.root.add_element @tracklist
    end
    print @str
    @str
  end
  def add(content)
    return unless content
    if content.mime
      return unless @audio_or_video =~ content.mime
    end
    @size+=1
    feed_title = content.feed_title
    feed_title = '' unless feed_title
    feed_title = sanitize feed_title
    title = content.title
    title = '' unless title
    title = sanitize title
    title = "#{content.pub_date.strftime('%Y.%m.%d')} - "+title if content.pub_date
    entry = ""
    case @playlisttype
    when :m3u
      feed_title = feed_title.gsub(/,/," ")
      title = title.gsub(/,/," ")
      entry = "#EXTINF:-1,[#{feed_title}] #{title}\n#{content.file.to_s}\n"
    when :pls
      entry = "File#{@size}:#{content.file}\nTitle#{@size}:[#{feed_title}] #{title}\nLength#{@size}:-1\n"
    when :asx
      entry = "  <entry><ref href='#{content.file.to_s.gsub(/&/,"&amp;").gsub(/'/,"&apos;").gsub(/"/,"&quot;")}' /></entry>\n"
    when :smil
      entry = "  <ref src='#{content.file.to_s.gsub(/&/,"&amp;").gsub(/'/,"&apos;").gsub(/"/,"&quot;")}' />\n"
    when :tox
      entry = "entry { \n\tidentifier = [#{feed_title}] #{title};\n\tmrl = #{content.file};\n};\n"
    when :xspf
      track = Element.new("track")
      @tracklist.add_element track
      title = Element.new("title")
      title.add_text "[#{feed_title}] #{title}"
      track.add_element title
      location = Element.new("location")
      location.add_text fileurl(content.file)
      track.add_element location
    end
    @str += entry
    print entry
    entry
  end
  def finish()
    res = ""
    case @playlisttype
    when :tox
      res = "# end "
    when :asx
      res = <<END
</asx>
END
    when :smil
      res = <<END
  </body>
</smil>
END
    when :pls
      res = "NumberOfEntries=#{@size}\nVersion=2\n"
    when :xspf
      @doc.write $stdout, 0
    end
    @str += res
    print res
    res
  end
  def to_s()
    if @doc
      @doc.to_s
    else
      @str
    end
  end
private
  def fileurl(path)
    res = ""
    loop do
      path, base = path.split
      if base.root?
        if base.to_s != "/"
          res = "/"+CGI.escape(base.to_s)+res
        end
        break
      end
      res = "/"+CGI.escape(base.to_s)+res
    end
    "file://"+res
  end
  def sanitize(text) #removes invisible characters from text
    return nil unless text
    res = ''
    text.each_byte() do |c|
      case c
      when 0..31, 127 #control chars
        res << ' '
      else
        res << c
      end
    end
    res
  end
end

