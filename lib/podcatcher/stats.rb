class Stats
  def initialize(dir)
    srand
    @now = Time.now
    @data = {'ping-probability' => 1.0}
    @server = URI.parse('http://www.podcatcherstats.com/podcatcher/ping')
    @server = URI.parse('http://0.0.0.0:3000/podcatcher/ping') if PODCATCHER_ENV == :development
    return unless dir
    return unless dir.directory?
    @file = dir + 'votes'
    if @file.exist? and @file.file?
      data = nil
      begin
        @file.open() do |f|
          data = YAML.load f
        end
      rescue Interrupt
        @file.delete
      rescue SystemExit
        exit 1
      rescue Exception
        @file.delete
      end
      if data.instance_of? Hash
    #   $stderr.puts "votes file read"
        data.each() do |key, value|
          case key
          when 'ping-probability'
            @data[key] = value unless value<0.0 or 1.0<value
          when 'last-session'
            @data[key] = value unless @now<value
          when 'last-ping'
            @data[key] = value unless @now<value
          end
        end
      else
    #   $stderr.puts "votes file could not be read"
        save
      end
    end
    if @data['last-ping']
      if @data['last-session']
        @data['last-ping'] = nil if @data['last-session']<@data['last-ping']
      else
        @data['last-ping'] = nil
      end
    end
    save unless @file.exist?
    exit 1 unless @file.file?
  end
  def ping(opt, feeds)
    return unless opt
    return unless feeds
    return if opt.simulate
    #constants
    max_sent_feeds = 50 #max nb of feed info to be sent
    #
    now = Time.now
    begin
      loop do
        break unless opt.vote
        break unless ping?
    #   $stderr.puts "ping: #{@server}"
        stats = Document.new
        stats.add_element 'downloading'
        #state
        stats.root.add_element state_element #(opt)
        #feeds
        sent_feeds = 0
        feeds.each() do |feed|
          if feed.size > 0 and feed[0].feedurl and feed[0].feedurl.size<255 and (not URI.parse(feed[0].feedurl).instance_of?(URI::Generic)) and sent_feeds < max_sent_feeds
            stats.root.add_element 'feed', {'url' => feed[0].feedurl}
            sent_feeds += 1
          end
        end
        break unless sent_feeds>0
        #send
        stats_str = ''
        stats.write stats_str
        if PODCATCHER_ENV != :production
          $stderr.puts "Sent:"
          $stderr.puts stats_str
        end
        change_state = nil
        Net::HTTP.start(@server.host, @server.port) do |http|
          resp = http.request_post @server.path, stats_str, 'User-Agent' => USER_AGENT, 'Content-Type' => 'application/xml', 'Connection' => 'close'
          if PODCATCHER_ENV != :production
            $stderr.puts "Received:"
            $stderr.puts "#{resp.body}"
          end
          change resp.body
        end
        @data['last-ping'] = now+0
        break
      end
    rescue Interrupt
  #   $stderr.puts "int1 #{$!}"
    rescue SystemExit
      exit 1
    rescue Exception
  #   $stderr.puts "exc #{$!}"
    end
    @data['last-session'] = now+0
    save
  # $stderr.puts "#{to_s}"
  end
  def ping_search(opt, query)
    return unless opt
    return unless query
    return if opt.simulate
    now = Time.now
    begin
      loop do
        break unless opt.vote
        break unless ping?
    #   $stderr.puts "ping.."
        stats = Document.new
        stats.add_element 'searching', {'query' => query}
        #state
        stats.root.add_element state_element
        #send
        stats_str = ''
        stats.write stats_str
    #   $stderr.puts stats_str
        change_state = nil
        Net::HTTP.start(@server.host, @server.port) do |http|
          resp = http.request_post @server.path, stats_str, 'User-Agent' => USER_AGENT, 'Content-Type' => 'application/xml', 'Connection' => 'close'
    #     $stderr.puts "#{resp.body}"
          change resp.body
        end
        @data['last-ping'] = now+0
        break
      end
    rescue Interrupt
  #   $stderr.puts "int1 #{$!}"
    rescue SystemExit
      exit 1
    rescue Exception
  #   $stderr.puts "exc #{$!}"
    end
    @data['last-session'] = now+0
    save
  # $stderr.puts "#{to_s}"
  end
  def to_s()
    res = ''
    if @data
      @data.each() do |key, value|
        res+= "#{key}: #{value}\n"
      end
    end
    res
  end
private
  def save()
    @file.open('w') do |f|
      YAML.dump @data, f
    end
  end
  def ping?()
    r = rand
  # $stderr.puts "random: #{r}, ping-probability: #{@data['ping-probability']}"
    return r < @data['ping-probability']
  end
  def change(doc_str)
    return unless doc_str
    begin
      change_state = Document.new doc_str
      loop do
        break unless change_state
        break unless change_state.root
        break unless change_state.root.name == 'state'
        #ping-probability
        ping = change_state.root.attributes['ping']
        if ping and ping.size>0
          ping = ping.to_f
          unless ping<0.0 or 1.0<ping
            @data['ping-probability'] = ping
          end
        end
        #
        break
      end
    rescue Interrupt
    rescue SystemExit
      exit 1
    rescue Exception
    end
  end
  def state_element #(opt=nil)
    state = Element.new 'state'
    state.add_attribute('ping', @data['ping-probability']) if @data['ping-probability']
    if @data['last-session']
      age_in_seconds = @now - @data['last-session'] #Float
      age_in_days = age_in_seconds/60.0/60.0/24.0
      state.add_attribute('age', age_in_days)
    end
  # return state unless opt
  # state.add_attribute('strategy', opt.strategy)
  # state.add_attribute('order', opt.order)
  # state.add_attribute('cache', opt.size / 1_000_000) if opt.size
  # state.add_attribute('content', opt.content_type.source) if opt.content_type and opt.content_type.source.size<80
    state
  end
end

