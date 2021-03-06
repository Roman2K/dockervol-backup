require 'utils'
require 'fileutils'

module Commands
  OUT = Pathname "out"

  def self.cmd_backup(rclone_dest, skip: "")
    log = Utils::Log.new
    skip = skip.split(",")

    dir = OUT.join Time.now.utc.strftime '%Y%m%dT%H%M%SZ'
    FileUtils.mkdir_p dir
    log[skip: skip, dir: dir].info "starting"

    vols = `docker volume ls -q`.split
    $?.success? or raise "`docker volume` failed"
    log[count: vols.size].info "found Docker volumes"

    finished = false
    rclone = Thread.new do
      Thread.current.abort_on_exception = true
      loop do
        sleep 1
        if was_finished = finished
          log["rclone"].info "finishing"
        end
        system "rclone", "move", "--exclude", "*.tmp",
          dir.to_s, "#{rclone_dest}/#{dir.basename}" \
          or raise "`rclone move` failed"
        break if was_finished
      end
      log["rclone"].info "finished"
    end

    vols.each do |vol|
      vlog = log[vol: vol]
      if skip.include? vol
        vlog.debug "skipping"
        next
      end
      if vol =~ /^[a-f0-9]{64}$/
        vlog.debug "skipping unnamed volume"
        next
      end
      vlog.info "backing up"
      dest = dir.join "#{vol}.tgz"
      tmp = dest.dirname.join("#{dest.basename}.tmp")
      size = Utils.retry 5, TarError, log: log["tar_vol retry"] do
        tar_vol vol, tmp
      end
      FileUtils.mv tmp, dest

      vlog[dest: dest.relative_path_from(OUT)].
        info "written %s" % [Utils::Fmt.size(size)]
    end
    finished = true

    log.info "waiting for rclone to finish"
    rclone.join

    dir.glob("**/*").empty? or raise "found leftover files"
    FileUtils.rm_r dir
  end

  def self.tar_vol(vol, f)
    IO.popen [
      "docker", "run", "--rm", "-v", "#{vol}:/mnt/volume",
      "-w", "/mnt", "bash", "-c", "tar czp volume",
    ] do |p|
      f.open('w') { |w| IO.copy_stream p, w }
    end.tap do
      case $?.exitstatus
      when 0
      when 1 then raise TarError
      else raise "`tar cp` failed"
      end
    end
  end

  class TarError < StandardError; end
end

if $0 == __FILE__
  require 'metacli'
  MetaCLI.new(ARGV).run Commands
end
