class Update
  def initialize(dir)
    @now = Time.now
    @data = {'last-check' => @now, 'latest-version' => PODCATCHER_VERSION, 'latest-version-description' => ''}
    @server = URI.parse('http://www.podcatcherstats.com/podcatcher/latest_release')
    @server = URI.parse('http://0.0.0.0:3000/podcatcher/latest_release') if PODCATCHER_ENV == :development
    return unless dir
    return unless dir.directory?
    @file = dir + 'updates'
    if @file.exist? and @file.file?
      begin
        data = nil
        @file.open() do |f|
          data = YAML.load f
        end
        if data.instance_of? Hash
          if newer_or_equal? data['latest-version']
            data.each() do |key, value|
              case key
              when 'last-check'
                @data[key] = value if value.instance_of? Time and value < @now
              when 'latest-version'
                @data[key] = value if value.instance_of? String
              when 'latest-version-description'
                @data[key] = value if value.instance_of? String
              end
            end
          end
        end
      rescue Interrupt
        @file.delete
      rescue SystemExit
        exit 1
      rescue Exception
        @file.delete
      end
    end
    save
    exit 1 unless @file.file?
  end
  def check()
    if @now - @data['last-check'] > 60.0 * 60.0 * 24 * 30 * UPDATE_CHECK_INTERVAL
      @data['last-check'] = @now
      begin
        Net::HTTP.start(@server.host, @server.port) do |http|
          resp = http.get(@server.path, {'User-Agent' => USER_AGENT, 'Connection' => 'close'})
          loop do
            break unless resp.code =~ Regexp.new('^2')
            doc = Document.new resp.body
            break unless doc and doc.root and doc.root.name == 'release'
            version = XPath.first doc.root, 'version'
            break unless version
            break unless newer? version.text
            description = XPath.first doc.root, 'description'
            if description
              description = description.text.strip
            else
              description = ''
            end
            @data['latest-version'] = version.join '.'
            @data['latest-version-description'] = description
            save
            break
          end
        # read resp.body
        end
      rescue Interrupt
      rescue SystemExit
        exit 1
      rescue Exception
      end
    end
    flash
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
  def flash()
    return unless newer? @data['latest-version'] #if equal? @data['latest-version']
    #constants
    line_length = 70
    p = '**** '
    #
    $stderr.puts ""
    $stderr.puts p+"New release:"
    $stderr.puts p+"Version #{@data['latest-version']} is available at #{PODCATCHER_WEBSITE}."
    if @data['latest-version-description'].size>0
      descr = []
      @data['latest-version-description'].each() do |line|
        descr =  descr + line.chomp.split(' ')
      end
      line = nil
      descr.each() do |word|
        if line and (line + ' ' + word).size>line_length
          $stderr.puts p+line
          line = nil
        end
        if line
          line += ' '+word
        else
          line = word
        end

      end
      $stderr.puts p+line if line
    end
    $stderr.puts ""
  end
  def save()
    @file.open('w') do |f|
      YAML.dump @data, f
    end
  end
  def compare_with(version) # Return values: -1: version<installed_version, 0: version==installed_version, 1: version>installed_version
    return -1 unless version
    version = version.strip.split '.'
    for i in 0...version.size
      version[i] = version[i].to_i
    end
    current_version = PODCATCHER_VERSION.strip.split '.'
    for i in 0...current_version.size
      current_version[i] = current_version[i].to_i
    end
    res = 0
    for i in 0...version.size
      break if i>=current_version.size
      if current_version[i]>version[i]
        res = -1
        break
      end
      if current_version[i]<version[i]
        res = 1
        break
      end
    end
    res
  end
  def newer?(version)
    compare_with(version) == 1
  end
  def newer_or_equal?(version)
    compare_with(version) != -1
  end
  def equal?(version)
    compare_with(version) == 0
  end
end

