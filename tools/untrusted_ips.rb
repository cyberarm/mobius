URLS = %w[
  https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/vpn/ipv4.txt
  https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/datacenter/ipv4.txt
  https://raw.githubusercontent.com/X4BNet/lists_torexit/main/ipv4.txt
]

require "excon"
require "stringio"

buffer = StringIO.new
path = "#{File.expand_path("./../conf", __dir__)}/untrusted_ips.dat"

URLS.each_with_index do |url, i|
  puts "Fetching #{url}..."
  response = Excon.get(url)

  if response.status == 200
    buffer.puts("#{'#' * (i + 1)} #{url}")
    buffer.write(response.body)
    buffer.puts
  else
    warn "Error for #{url}: #{response.status}"
  end
end

File.write(path, buffer.string)
puts "Done."
puts
