#require 'set'
require 'fileutils'
require 'digest'
require 'exifr'

Output_dir = 'E:/media_out'
Photos_dir = 'E:/cassiopeia/photos_deleteme'
Convert_path = "E:/cassiopeia/programs/imagemagick/convert.exe"
Extensions = { photo: %w(jpg jpeg), video: %w(mp4 avi 3gp) }
PreferredPhotoWidth = 1920
PreferredPhotoHeight = 1080

file_paths = Dir[File.join(Photos_dir, '**', '*')].reject { |path| File.directory? path }

#extensions = Hash.new { |h, k| h[k] = [] }
sizes = Hash.new { |h, k| h[k] = [] }
file_paths.each do |path|
#    extensions[File.extname(path)[1..-1].downcase].push path
    sizes[File.size path].push path
end
#sizes.reject! { |size, paths| paths.length == 1 }

#extensions.each { |extension, paths| puts "#{extension}: #{paths.count}" }
#
#sizes.each do |size, paths|
#    puts "#{size}:"
#    paths.each { |path| puts "  - #{path}" }
#end
#
#diff_names = Hash.new
#sizes.each do |size, paths|
#    current = Set.new
#    paths.each do |path_i|
#        paths.each do |path_j|
#            next if path_i == path_j
#            current << path_i << path_j unless File.basename(path_i) == File.basename(path_j)
#        end
#    end
#    diff_names[size] = current unless current.empty?
#end
#
#diff_names.each do |size, paths|
#    puts "#{size}:"
#    paths.each { |path| puts "  - #{path}" }
#end

unique_files = []
sizes.each do |size, paths_i|
    if paths_i.count == 1
        unique_files << paths_i.first
        next
    end
    checksums = Hash.new { |h, k| h[k] = [] }
    paths_i.each { |path| checksums[Digest::MD5.file(path).hexdigest] << path }
    checksums.each do |checksum, paths_j|
        if paths_j.count == 1
            unique_files << paths_j.first
            next
        end
        unique_files << paths_j.min_by { |path| File.stat(path).mtime }
    end
end

puts "all file count: #{file_paths.count}", "unique file count: #{unique_files.count}"

files_by_type = Hash.new { |h, k| h[k] = [] }
unique_files.each do |path|
    extension = File.extname(path)[1..-1].downcase
    Extensions.each do |type, extensions|
        if extensions.include? extension
            files_by_type[type] << path
            break
        end
    end
end

files_by_type.each { |type, paths| puts "#{type}: #{paths.count}" }

Jpg = Struct.new(:path, :metadata, :time)

photos_by_cam = Hash.new { |h, k| h[k] = [] }
files_by_type[:photo].each.with_index do |path, index|
    puts "#{index + 1}/#{files_by_type[:photo].count}"
    jpg = Jpg.new path, EXIFR::JPEG.new(path), File.stat(path).mtime
    photos_by_cam["#{jpg.metadata.make} #{jpg.metadata.model}".gsub(/[\W&&[^ ]]+/, "").scan(/\b\w+\b/).uniq.join " "] << jpg
end

#EXIFR::JPEG.new(files_by_type[:photo].first).to_hash.each { |key, value| puts "#{key}: #{value}" }

photos_by_cam.each do |cam, photos|
    puts "#{cam}: #{photos.count}"

    photos.sort_by! { |photo| photo.time }

    out_dir = File.join(Output_dir, cam)
    FileUtils.mkdir_p(out_dir)

    photos.each.with_index do |photo, index|
        filename = "#{index + 1} #{photo.time.strftime "%a, %b %e, %Y %H-%M"}.jpg"
        out_path = File.join(out_dir, filename)
        
        if photo.metadata.width > PreferredPhotoWidth && photo.metadata.height > PreferredPhotoHeight
            resize_arg = "-resize " + if photo.metadata.width > photo.metadata.height
                                          "x#{PreferredPhotoHeight}"
                                      else
                                          PreferredPhotoWidth
                                      end
            system(%{"#{Convert_path}" "#{photo.path}" #{resize_arg} "#{out_path}"})
        else
            FileUtils.cp photo.path, out_path
        end

        File.utime File.atime(photo.path), photo.time, out_path
    end
end
