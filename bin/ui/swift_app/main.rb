dir = __dir__
system("#{dir}/package_app.sh", exception: true)
system("open", "#{dir}/AdvancedBibleQueryApp.app", exception: true)
