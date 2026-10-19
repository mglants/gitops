# frozen_string_literal: true

require 'fileutils'
require 'find'
require 'nokogiri'
require 'optparse'

module BigBlueButton
  # BBB's deleteRecordings API moves every format into deleted/<format>/<id>.
  # metadata.xml is rewritten at deletion; the directory mtime is not reliable.
  class DeletedRecordingCleanup
    ID = /\A[0-9a-f]{40}-\d+\z/
    FORMAT = /\A[a-zA-Z0-9_-]+\z/

    def initialize(root:, days:, apply: false, now: Time.now, output: $stdout)
      raise ArgumentError, 'Retention must be at least one day' unless days >= 1
      @root = File.expand_path(root)
      raise ArgumentError, 'Root must be a real directory' unless File.directory?(@root) && File.realpath(@root) == @root && @root != '/'
      @cutoff, @apply, @output = now - days * 86_400, apply, output
    end

    def formats(base)
      return [] unless File.directory?(base) && !File.symlink?(base)
      Dir.children(base).select { |name| FORMAT.match?(name) && File.directory?(File.join(base, name)) && !File.symlink?(File.join(base, name)) }
    end

    def format_paths(section, id)
      base = File.join(@root, section)
      formats(base).map { |format| File.join(base, format, id) }.select { |path| File.exist?(path) || File.symlink?(path) }
    end

    def safe_tree?(path)
      return true unless File.exist?(path) || File.symlink?(path)
      # Check ancestors too: FileUtils must never traverse a symlinked parent.
      relative = path.delete_prefix(@root + '/')
      return false if relative == path || relative.split('/').include?('..')
      current = @root
      relative.split('/').each do |part|
        current = File.join(current, part)
        return false if File.symlink?(current)
      end
      Find.find(path) do |file|
        return false if File.symlink?(file) || File.mtime(file) > @cutoff
      end
      true
    end

    def run
      %w[deleted published unpublished recording recording/raw recording/process recording/publish recording/status recording/summary captions].each do |section|
        raise ArgumentError, "Unsafe storage path: #{section}" if File.symlink?(File.join(@root, section))
      end
      base = File.join(@root, 'deleted')
      ids = formats(base).flat_map { |format| Dir.children(File.join(base, format)) }.uniq.grep(ID).sort
      @output.puts "Scan #{ids.length} deleted recordings (#{@apply ? 'apply' : 'dry-run'})"
      ids.each { |id| clean(id) }
    end

    def clean(id)
      deleted = format_paths('deleted', id)
      return if deleted.empty?
      # A restored or partially deleted recording is never eligible.
      unless (format_paths('published', id) + format_paths('unpublished', id)).empty?
        @output.puts "Skip #{id}: an available format still exists"
        return
      end
      eligible = deleted.all? do |path|
        metadata = File.join(path, 'metadata.xml')
        next false unless File.file?(metadata) && !File.symlink?(metadata) && File.mtime(metadata) <= @cutoff
        xml = Nokogiri::XML(File.read(metadata)) { |config| config.strict.nonet }
        xml.at_xpath('/recording/id')&.text == id && xml.at_xpath('/recording/state')&.text == 'deleted'
      end
      return unless eligible

      paths = [File.join(@root, 'recording', 'raw', id), File.join(@root, 'recording', 'summary', id),
               File.join(@root, 'captions', id), File.join(@root, id)]
      %w[recording/process recording/publish].each { |section| paths.concat(format_paths(section, id)) }
      status = File.join(@root, 'recording', 'status')
      if File.directory?(status) && !File.symlink?(status)
        Dir.children(status).each do |stage|
          next unless FORMAT.match?(stage) && File.directory?(File.join(status, stage)) && !File.symlink?(File.join(status, stage))
          Dir.children(File.join(status, stage)).each do |name|
            paths << File.join(status, stage, name) if name.match?(/\A#{Regexp.escape(id)}(?:-[a-zA-Z0-9_-]+)?\.(?:done|fail|norecord)\z/)
          end
        end
      end
      # Recent writes indicate a processing retry. Do not remove its inputs.
      unless (paths + deleted).all? { |path| safe_tree?(path) }
        @output.puts "Skip #{id}: recent activity or unsafe path"
        return
      end
      lock_path = File.join(@root, 'recording', 'summary', id, 'lock')
      lock = File.open(lock_path, 'r+') if File.file?(lock_path)
      if lock && !lock.flock(File::LOCK_EX | File::LOCK_NB)
        @output.puts "Skip #{id}: summary worker is active"
        return
      end
      # Recheck availability after taking the same lock as the summary worker.
      return unless (format_paths('published', id) + format_paths('unpublished', id)).empty?
      @output.puts "#{@apply ? 'Purge' : 'Would purge'} #{id} (#{deleted.length} deleted formats plus processing cache)"
      return unless @apply
      # Delete tombstones last so an interrupted cleanup can be retried.
      cache = File.join(@root, 'recording', 'summary', id)
      paths.uniq.reject { |path| path == cache }.each { |path| FileUtils.remove_entry_secure(path) if File.exist?(path) }
      # NFS cannot remove an open lock file without creating a .nfs placeholder.
      # Raw inputs are already gone, so a new summary attempt cannot proceed.
      lock&.close
      lock = nil
      ([cache] + deleted).uniq.each { |path| FileUtils.remove_entry_secure(path) if File.exist?(path) }
    ensure
      lock&.close
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { root: '/var/bigbluebutton', days: Integer(ENV.fetch('BBB_DELETED_RETENTION_DAYS', '1')), apply: false }
  OptionParser.new do |parser|
    parser.on('--root PATH') { |value| options[:root] = value }
    parser.on('--days N', Integer) { |value| options[:days] = value }
    parser.on('--apply') { options[:apply] = true }
  end.parse!
  BigBlueButton::DeletedRecordingCleanup.new(**options).run
end
