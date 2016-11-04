#require 'set'
require 'fileutils'
require 'digest'
require 'exifr'
require 'terminal-table'

RESIZE_COMPRESSION = false
OUTPUT_DIR = 'E:/media_out'
#INPUT_DIR = 'E:/cassiopeia/photos_deleteme'
INPUT_DIR = 'E:/cassiopeia/photos'
CONVERT_PATH = "E:/cassiopeia/programs/imagemagick/convert.exe" # imagemagick's convert.exe
MEDIA_EXTENSIONS = { photo: %w(jpg jpeg), video: %w(mp4 avi 3gp) }
PREFERRED_PHOTO_WIDTH = 1920
PREFERRED_PHOTO_HEIGHT = 1080
FILENAME_FORMAT = "%a, %b %0e, %Y %H-%M" # Sun, Nov 05, 2016 13:37
FILENAME_FORMAT_INCLUDE_INDEX = true

VIDEO_DIR_NAME = "videos"

EXTENSION_WORD = "Extension"
FILE_COUNT_WORD = "Number"
SIZE_WORD = "Size"
MEDIA_TYPE_WORD = "Media type"
TOTAL_WORD = "TOTAL"

ALIGN_TABLE = [:center, :right, :right]

FileUtils.mkdir_p OUTPUT_DIR
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

puts "Handling videos..."
out_dir = File.join(OUTPUT_DIR, VIDEO_DIR_NAME)
FileUtils.mkdir_p out_dir
files_by_type[:video].sort_by! { |file| file.stats.mtime }
files_by_type[:video].each.with_index do |file, index|
    print "#{index + 1}/#{files_by_type[:video].count}"
#    filename = " #{FILENAME_FORMAT_INCLUDE_INDEX ? "#{index + 1} " : ""}#{file.stats.mtime.strftime FILENAME_FORMAT}#{File.extname(file.path).downcase}"
    filename = File.basename file.path
    puts " #{filename} #{format_size file.stats.size} #{file.stats.mtime.strftime FILENAME_FORMAT}"
    out_path = File.join out_dir, filename
    FileUtils.cp file.path, out_path
    File.utime file.stats.atime, file.stats.mtime, out_path
end
puts "Done"

Jpg = Struct.new :file, :metadata

print "Collecting photo metadata..."
photos_by_cam = Hash.new { |h, k| h[k] = [] }
files_by_type[:photo].each.with_index do |file, index|
    jpg = Jpg.new file, EXIFR::JPEG.new(file.path)
    photos_by_cam["#{jpg.metadata.make} #{jpg.metadata.model}".gsub(/[\W&&[^ ]]+/, "").scan(/\b\w+\b/).uniq.join " "] << jpg
end
puts " Done"

puts "Handling photos..."
count = photos_by_cam.map { |cam, photos| photos.count }.inject(:+)
i = 0
photos_by_cam.each do |cam, photos|
    photos.sort_by! { |photo| photo.file.stats.mtime }

    out_dir = File.join OUTPUT_DIR, cam
    FileUtils.mkdir_p out_dir

    photos.each.with_index do |photo, index|
        print "#{i += 1}/#{count}"

        filename = "#{FILENAME_FORMAT_INCLUDE_INDEX ? "#{index + 1} " : ""}#{photo.file.stats.mtime.strftime FILENAME_FORMAT}.jpg"
        print " #{File.join cam, filename}"
        out_path = File.join(out_dir, filename)
        
        if RESIZE_COMPRESSION && photo.metadata.width > PREFERRED_PHOTO_WIDTH && photo.metadata.height > PREFERRED_PHOTO_HEIGHT
            puts " RESIZE"
            resize_arg = "-resize " + if photo.metadata.width > photo.metadata.height
                                          "x#{PREFERRED_PHOTO_HEIGHT}"
                                      else
                                          PREFERRED_PHOTO_WIDTH.to_s
                                      end
            system(%{"#{CONVERT_PATH}" "#{photo.file.path}" #{resize_arg} "#{out_path}"})
        else
            puts " COPY"
            FileUtils.cp photo.file.path, out_path
        end

        File.utime photo.file.stats.atime, photo.file.stats.mtime, out_path
    end
end
puts "Done"
