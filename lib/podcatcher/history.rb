class History
  def initialize(dir)
    @history = dir + "history"
    @history_old = dir + "history-old"
    unless @history.exist?
      @history_old.rename @history if @history_old.exist?
    end
    @history.open("w"){|f|}unless @history.exist?
    exit 1 unless @history.file?
    @history_old.delete if @history_old.exist?
  end
  def mark_old_content(feeds)
    feeds.each() do |feed|
      feed.each() do |content|
        content.in_history = false
      end
    end
    @history.each_line() do |url|
      url = url.chomp
      feeds.each() do |feed|
        feed.each() do |content|
          next if content.in_history
          content.in_history = content.url == url
        end
      end
    end
  end
  def add(content)
    begin
      @history.open("a") do |f|
        f.puts content.url
      end
    rescue Interrupt, SystemExit
      exit 1
    rescue Exception
      $stderr.puts "Error: history file could not be updated"
    end
  end
  def trim(limit)
    begin
      history_size = 0
      @history.each_line() do |url|
        history_size += 1
      end
      if history_size > limit #shrink
        @history_old.delete if @history_old.exist?
        @history.rename @history_old
        @history.open("w") do |f|
          @history_old.each_line() do |url|
            f.print(url) if history_size <= limit
            history_size -= 1
          end
        end
        @history_old.unlink
      end
    rescue Interrupt, SystemExit
      exit 1
    rescue Exception
      $stderr.puts "Error: failure during history file clean-up."
    end if limit
  end
end

