run.ui:
	ruby bin/ui/swift_app/main.rb

do.test.all:
	find tests -type f -name 'test*.rb' | while read -r t; do \
		ruby "$$t"; \
	done
