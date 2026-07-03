Dir[File.join(__dir__, 'shared/*.rb')].each { |rb|
  require rb
}

Dir[File.join(__dir__, 'domain/**/*.rb')].each { |rb|
  require rb
}