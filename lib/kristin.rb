require 'kristin/version'
require 'open-uri'
require 'net/http'
require 'posix-spawn'

module Kristin
  class Pdf2HtmlExError < StandardError
    attr_accessor :pdf2htmlex_out, :pdf2htmlex_err

    def initialize(msg, out_str, err_str)
      @pdf2htmlex_out = out_str
      @pdf2htmlex_err = err_str
      super(msg)
    end
  end

  class Converter
    def initialize(source, target, options = {})
      @options = options
      @source = source
      @target = target
    end

    def convert
      raise IOError, "Can't find pdf2htmlex executable in PATH" unless command_available?

      src = determine_source(@source)
      opts = process_options.split(' ')
      args = [pdf2htmlex_command, opts, src, @target].flatten
      begin
        pid, stdin, stdout, stderr = POSIX::Spawn.popen4(*args)
        stdin.close
        out = stdout.read
        err = stderr.read
        Process.waitpid(pid)
        raise Kristin::Pdf2HtmlExError.new "Could not convert #{src}", out, err if $?.exitstatus != 0
      ensure
        [stdin, stdout, stderr].each { |io| io.close unless io.closed? }
      end
    end

    private

    def process_options
      opts = []

      if @target && (@target == File.absolute_path(@target))
        abs_path = File.absolute_path(@target)
        @target = File.basename(@target)
        @options[:dest_dir] = File.absolute_path(abs_path.gsub(@target, ''))
      end

      opts.push('--process-outline 0') if @options[:process_outline] == false
      opts.push("--first-page #{@options[:first_page]}") if @options[:first_page]
      opts.push("--last-page #{@options[:last_page]}") if @options[:last_page]
      opts.push("--hdpi #{@options[:hdpi]}") if @options[:hdpi]
      opts.push("--vdpi #{@options[:vdpi]}") if @options[:vdpi]
      opts.push("--zoom #{@options[:zoom]}") if @options[:zoom]
      opts.push("--fit-width #{@options[:fit_width]}") if @options[:fit_width]
      opts.push("--fit-height #{@options[:fit_height]}") if @options[:fit_height]
      opts.push('--split-pages 1') if @options[:split_pages]
      opts.push("--data-dir #{@options[:data_dir]}") if @options[:data_dir]
      opts.push("--dest-dir #{@options[:dest_dir]}") if @options[:dest_dir]
      opts.push("--tmp-dir #{@options[:tmp_dir]}") if @options[:tmp_dir]
      opts.join(' ')
    end

    def command_available?
      pdf2htmlex_command
    end

    def pdf2htmlex_command
      cmd = nil
      cmd = 'pdf2htmlex' if which('pdf2htmlex')
      cmd = 'pdf2htmlEX' if which('pdf2htmlEX')
    end

    def which(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable? exe
        end
      end
      nil
    end

    def random_source_name
      rand(16**16).to_s(16)
    end

    def download_file(source)
      tmp_file = "/tmp/#{random_source_name}.pdf"
      File.open(tmp_file, 'wb') do |saved_file|
        open(URI.encode(source), 'rb') do |read_file|
          saved_file.write(read_file.read)
        end
      end

      tmp_file
    end

    def determine_source(source)
      is_file = File.exist?(source) && !File.directory?(source)
      is_http = URI(source).scheme == 'http'
      is_https = URI(source).scheme == 'https'
      raise IOError, "Source (#{source}) is neither a file nor an URL." unless is_file || is_http || is_https

      is_file ? source : download_file(source)
    end
  end

  def self.convert(source, target, options = {})
    Converter.new(source, target, options).convert
  end
end
