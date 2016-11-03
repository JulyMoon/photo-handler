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
SIZE_WORD = "Size"
MEDIA_TYPE_WORD = "Media type"
TOTAL_WORD = "TOTAL"

ALIGN_TABLE = [:center, :right, :right]

fail "ERROR: The output directory already contains files" if Dir.new(OUTPUT_DIR).count > 2

print "Scanning for files..."
file_paths = Dir[File.join(INPUT_DIR, '**', '*')].reject { |path| File.directory? path }
puts " Done"

def extension_of path
    File.extname(path)[1..-1].downcase
end

FileWithStats = Struct.new :path, :stats

files_by_ext = Hash.new 0
files_by_size = Hash.new { |h, k| h[k] = [] }
size_by_ext = Hash.new 0
file_paths.each do |path|
    file = FileWithStats.new path, File.stat(path)
    ext = extension_of path
    files_by_size[file.stats.size] << file
    files_by_ext[ext] += 1
    size_by_ext[ext] += file.stats.size
end

def format_size size
    "%.02f MiB" % (size.to_f / (2**20))
end

table = Terminal::Table.new :headings => [EXTENSION_WORD, FILE_COUNT_WORD, SIZE_WORD],
    :rows => files_by_ext.map { |ext, count| [ext, count, format_size(size_by_ext[ext])] }
table.add_separator
table.add_row [TOTAL_WORD, files_by_ext.values.inject(:+), format_size(size_by_ext.values.inject(:+))]
ALIGN_TABLE.each.with_index { |align, index| table.align_column index, align }
puts table

print "Discarding the duplicates..."
unique_files = []
files_by_size.each do |size, files_i|
    if files_i.count == 1
        unique_files << files_i.first
        next
    end
    checksums = Hash.new { |h, k| h[k] = [] }
    files_i.each { |file| checksums[Digest::MD5.file(file.path).hexdigest] << file }
    checksums.each do |checksum, files_j|
        if files_j.count == 1
            unique_files << files_j.first
            next
        end
        unique_files << files_j.min_by { |file| file.stats.mtime }
    end
end
puts " Done"

puts "#{file_paths.count - unique_files.count} duplicates discarded", "Unique file count: #{unique_files.count}"

print "Sorting into types..."
files_by_type = Hash.new { |h, k| h[k] = [] }
unique_files.each do |file|
    extension = extension_of file.path
    MEDIA_EXTENSIONS.each do |type, extensions|
        if extensions.include? extension
            files_by_type[type] << file
            break
        end
    end
end
puts " Done"

size_by_type = Hash[files_by_type.map { |type, files| [type, files.map { |file| file.stats.size }.inject(:+)] }]
table = Terminal::Table.new :headings => [MEDIA_TYPE_WORD, FILE_COUNT_WORD, SIZE_WORD],
    :rows => files_by_type.map { |type, files| [type, files.count, format_size(size_by_type[type])] }
ALIGN_TABLE.each.with_index { |align, index| table.align_column index, align }
puts table

exit

files_by_type.each { |type, paths| puts "#{type}: #{paths.count}" }

Jpg = Struct.new :path, :metadata, :time

photos_by_cam = Hash.new { |h, k| h[k] = [] }
files_by_type[:photo].each.with_index do |path, index|
#    puts "#{index + 1}/#{files_by_type[:photo].count}"
    jpg = Jpg.new path, EXIFR::JPEG.new(path), File.stat(path).mtime
    photos_by_cam["#{jpg.metadata.make} #{jpg.metadata.model}".gsub(/[\W&&[^ ]]+/, "").scan(/\b\w+\b/).uniq.join " "] << jpg
end

count = photos_by_cam.map { |cam, photos| photos.count }.inject(:+)
i = 0
photos_by_cam.each do |cam, photos|
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
