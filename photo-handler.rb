#require 'set'
require 'fileutils'
require 'digest'
require 'exifr'
require 'terminal-table'

OUTPUT_DIR = 'E:/media_out'
#INPUT_DIR = 'E:/cassiopeia/photos_deleteme'
INPUT_DIR = 'E:/cassiopeia/photos'
CONVERT_PATH = "E:/cassiopeia/programs/imagemagick/convert.exe" # imagemagick's convert.exe
MEDIA_EXTENSIONS = { photo: %w(jpg jpeg), video: %w(mp4 avi 3gp) }
PREFERRED_PHOTO_WIDTH = 1920
PREFERRED_PHOTO_HEIGHT = 1080
FILENAME_FORMAT = "%a, %b %0e, %Y %H-%M" # Sun, Nov 05, 2016 13:37
FILENAME_FORMAT_INCLUDE_INDEX = true

EXTENSION_WORD = "Extension"
FILE_COUNT_WORD = "Number"
EXTENSION_SIZE_WORD = "Size"
TOTAL_WORD = "TOTAL"

ALIGN_TABLE = [:center, :right, :right]

fail "ERROR: The output directory already contains files" if Dir.new(OUTPUT_DIR).count > 2

print "Scanning for files... "
file_paths = Dir[File.join(INPUT_DIR, '**', '*')].reject { |path| File.directory? path }
puts "Done"

def extension_of path
    File.extname(path)[1..-1].downcase
end

files_by_ext = Hash.new 0
files_by_size = Hash.new { |h, k| h[k] = [] }
size_by_ext = Hash.new 0
file_paths.each do |path|
    size = File.size path
    ext = extension_of path
    files_by_size[size] << path
    files_by_ext[ext] += 1
    size_by_ext[ext] += size
end

def format_size size
    "%.02f MiB" % (size.to_f / (2**20))
end

table = Terminal::Table.new :headings => [EXTENSION_WORD, FILE_COUNT_WORD, EXTENSION_SIZE_WORD],
    :rows => files_by_ext.map { |ext, count| [ext, count, format_size(size_by_ext[ext])] }
table.add_separator
table.add_row [TOTAL_WORD, files_by_ext.values.inject(:+), format_size(size_by_ext.values.inject(:+))]
ALIGN_TABLE.each.with_index { |align, index| table.align_column index, align }
puts table

print "Discarding the duplicates..."
unique_files = []
files_by_size.each do |size, paths_i|
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
puts " Done"

exit

puts "all file count: #{file_paths.count}", "unique file count: #{unique_files.count}"

files_by_type = Hash.new { |h, k| h[k] = [] }
unique_files.each do |path|
    extension = File.extname(path)[1..-1].downcase
    MEDIA_EXTENSIONS.each do |type, extensions|
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
#    puts "#{index + 1}/#{files_by_type[:photo].count}"
    jpg = Jpg.new path, EXIFR::JPEG.new(path), File.stat(path).mtime
    photos_by_cam["#{jpg.metadata.make} #{jpg.metadata.model}".gsub(/[\W&&[^ ]]+/, "").scan(/\b\w+\b/).uniq.join " "] << jpg
end

#EXIFR::JPEG.new(files_by_type[:photo].first).to_hash.each { |key, value| puts "#{key}: #{value}" }

count = photos_by_cam.map { |cam, photos| photos.count }.inject(:+)
i = 0
photos_by_cam.each do |cam, photos|
#    puts "#{cam}: #{photos.count}"

    photos.sort_by! { |photo| photo.time }

    out_dir = File.join(OUTPUT_DIR, cam)
    FileUtils.mkdir_p(out_dir)

    photos.each.with_index do |photo, index|
        puts "#{i += 1}/#{count}"

        filename = "#{FILENAME_FORMAT_INCLUDE_INDEX ? "#{index + 1} " : ""}#{photo.time.strftime FILENAME_FORMAT}.jpg"
        out_path = File.join(out_dir, filename)
        
        if photo.metadata.width > PREFERRED_PHOTO_WIDTH && photo.metadata.height > PREFERRED_PHOTO_HEIGHT
            resize_arg = "-resize " + if photo.metadata.width > photo.metadata.height
                                          "x#{PREFERRED_PHOTO_HEIGHT}"
                                      else
                                          PREFERRED_PHOTO_WIDTH
                                      end
            system(%{"#{CONVERT_PATH}" "#{photo.path}" #{resize_arg} "#{out_path}"})
        else
            FileUtils.cp photo.path, out_path
        end

        File.utime File.atime(photo.path), photo.time, out_path
    end
end
