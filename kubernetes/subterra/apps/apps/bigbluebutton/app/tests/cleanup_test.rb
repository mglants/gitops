# frozen_string_literal: true
require 'tmpdir'
require 'stringio'
require ENV.fetch('BBB_CLEANUP_SCRIPT', '/config/cleanup.rb')

class CleanupTest
  ID = 'a' * 40 + '-1000'
  def assert(condition, message = 'Cleanup regression failed')
    raise message unless condition
  end

  def fixture
    Dir.mktmpdir do |root|
      now = Time.now
      paths = ["deleted/summary/#{ID}", "deleted/presentation/#{ID}", "recording/raw/#{ID}",
               "recording/process/summary/#{ID}", "recording/summary/#{ID}"]
      paths.each do |part|
        folder = File.join(root, part)
        FileUtils.mkdir_p(folder)
        File.write(File.join(folder, 'synthetic.txt'), 'Synthetic cleanup fixture')
      end
      paths.first(2).each do |part|
        File.write(File.join(root, part, 'metadata.xml'), "<recording><id>#{ID}</id><state>deleted</state></recording>")
      end
      lock = File.join(root, 'recording/summary', ID, 'lock')
      File.write(lock, '')
      Find.find(root) { |path| File.utime(now - 3 * 86_400, now - 3 * 86_400, path) }
      yield root, now, lock
    end
  end

  def run_cleanup(root, now, apply: true)
    output = StringIO.new
    BigBlueButton::DeletedRecordingCleanup.new(root: root, days: 1, apply: apply, now: now, output: output).run
    output.string
  end

  def test_dry_run_and_full_purge_include_raw_and_ai_cache
    fixture do |root, now, _lock|
      output = run_cleanup(root, now, apply: false)
      assert output.include?('Would purge')
      assert File.directory?(File.join(root, 'recording/summary', ID))
      run_cleanup(root, now)
      assert !File.exist?(File.join(root, 'deleted/summary', ID))
      assert !File.exist?(File.join(root, 'deleted/presentation', ID))
      assert !File.exist?(File.join(root, 'recording/raw', ID))
      assert !File.exist?(File.join(root, 'recording/summary', ID))
      assert !File.exist?(File.join(root, 'recording/process/summary', ID))
      run_cleanup(root, now) # Re-running is harmless.
    end
  end

  def test_recent_deletion_uses_metadata_time_not_old_directory_time
    fixture do |root, now, _lock|
      path = File.join(root, 'deleted/summary', ID, 'metadata.xml')
      File.utime(now, now, path)
      run_cleanup(root, now)
      assert File.directory?(File.join(root, 'recording/raw', ID))
    end
  end

  def test_recent_processing_activity_prevents_deletion
    fixture do |root, now, _lock|
      path = File.join(root, 'recording/raw', ID, 'synthetic.txt')
      File.utime(now, now, path)
      run_cleanup(root, now)
      assert File.directory?(File.join(root, 'deleted/summary', ID))
    end
  end

  def test_available_or_restored_format_prevents_deletion
    fixture do |root, now, _lock|
      FileUtils.mkdir_p(File.join(root, 'unpublished/video', ID))
      run_cleanup(root, now)
      assert File.directory?(File.join(root, 'recording/summary', ID))
    end
  end

  def test_active_summary_lock_prevents_deletion
    fixture do |root, now, path|
      File.open(path, 'r+') do |lock|
        lock.flock(File::LOCK_EX)
        output = run_cleanup(root, now)
        assert output.include?('worker is active')
        assert File.directory?(File.join(root, 'recording/summary', ID))
      end
    end
  end

  def test_symlinks_and_invalid_identifiers_are_not_followed
    fixture do |root, now, _lock|
      Dir.mktmpdir do |outside|
        target = File.join(root, 'recording/summary', ID, 'linked')
        File.symlink(outside, target)
        run_cleanup(root, now)
        assert File.directory?(File.join(root, 'deleted/summary', ID))
        assert File.directory?(outside)
      end
    end
  end

  def test_invalid_identifier_and_unrelated_recordings_are_preserved
    fixture do |root, now, _lock|
      unrelated = File.join(root, 'recording/raw', 'b' * 40 + '-1000')
      invalid = File.join(root, 'deleted/summary/not-a-recording')
      FileUtils.mkdir_p([unrelated, invalid])
      run_cleanup(root, now)
      assert File.directory?(unrelated)
      assert File.directory?(invalid)
      assert !File.directory?(File.join(root, 'recording/raw', ID))
    end
  end

  def test_no_zero_day_retention
    fixture do |root, now, _lock|
      rejected = false
      begin
        BigBlueButton::DeletedRecordingCleanup.new(root: root, days: 0, now: now)
      rescue ArgumentError
        rejected = true
      end
      assert rejected
    end
  end
end

CleanupTest.instance_methods(false).grep(/^test_/).each do |name|
  CleanupTest.new.public_send(name)
  puts "#{name}: PASS"
end
