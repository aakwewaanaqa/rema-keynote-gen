Dir['shared/*.rb'].each { |rb|
  require_relative rb
}

Dir['domain/**/*.rb'].each { |rb|
  require_relative rb
}